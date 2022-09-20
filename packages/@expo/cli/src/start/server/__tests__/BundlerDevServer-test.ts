import openBrowserAsync from 'better-opn';
import { vol } from 'memfs';

import * as Log from '../../../log';
import { BundlerDevServer, BundlerStartOptions, DevServerInstance } from '../BundlerDevServer';
import { UrlCreator } from '../UrlCreator';
import { getPlatformBundlers } from '../platformBundlers';

jest.mock(`../../../log`);
jest.mock('../AsyncNgrok');
jest.mock('../DevelopmentSession');
jest.mock('../../platforms/ios/ApplePlatformManager', () => {
  class ApplePlatformManager {
    openAsync = jest.fn(async () => ({ url: 'mock-apple-url' }));
  }
  return {
    ApplePlatformManager,
  };
});
jest.mock('../../platforms/android/AndroidPlatformManager', () => {
  class AndroidPlatformManager {
    openAsync = jest.fn(async () => ({ url: 'mock-android-url' }));
  }
  return {
    AndroidPlatformManager,
  };
});

const originalCwd = process.cwd();

beforeAll(() => {
  process.chdir('/');
});

beforeEach(() => {
  vol.reset();
});

afterAll(() => {
  process.chdir(originalCwd);
});

class MockBundlerDevServer extends BundlerDevServer {
  get name(): string {
    return 'fake';
  }

  public async startAsync(options: BundlerStartOptions): Promise<DevServerInstance> {
    const port = options.port || 3000;
    this.urlCreator = new UrlCreator(
      {
        scheme: options.https ? 'https' : 'http',
        ...options.location,
      },
      {
        port,
        getTunnelUrl: this.getTunnelUrl.bind(this),
      }
    );

    const protocol = 'http';
    const host = 'localhost';
    this.setInstance({
      // Server instance
      server: { close: jest.fn((fn) => fn()) },
      // URL Info
      location: {
        url: `${protocol}://${host}:${port}`,
        port,
        protocol,
        host,
      },
      middleware: {},
      // Match the native protocol.
      messageSocket: {
        broadcast: jest.fn(),
      },
    });
    await this.postStartAsync(options);

    return this.getInstance();
  }

  getPublicUrlCreator() {
    return this.urlCreator;
  }
  getNgrok() {
    return this.ngrok;
  }
  getDevSession() {
    return this.devSession;
  }

  protected getConfigModuleIds(): string[] {
    return ['./fake.config.js'];
  }

  public getExpoGoUrl(
    platform: 'simulator' | 'emulator' | null,
    isDevelopmentBuildInstalled: boolean
  ) {
    return super.getExpoGoUrl(platform, isDevelopmentBuildInstalled);
  }
}

async function getRunningServer() {
  const devServer = new MockBundlerDevServer('/', getPlatformBundlers({}));
  await devServer.startAsync({ location: {} });
  return devServer;
}

describe('broadcastMessage', () => {
  it(`sends a message`, async () => {
    const devServer = await getRunningServer();
    devServer.broadcastMessage('reload', { foo: true });
    expect(devServer.getInstance().messageSocket.broadcast).toBeCalledWith('reload', { foo: true });
  });
});

describe('openPlatformAsync', () => {
  it(`opens a project in the browser`, async () => {
    const devServer = await getRunningServer();
    const { url } = await devServer.openPlatformAsync('desktop');
    expect(url).toBe('http://localhost:3000');
    expect(openBrowserAsync).toBeCalledWith('http://localhost:3000');
  });

  for (const platform of ['ios', 'android']) {
    for (const isDevClient of [false, true]) {
      const runtime = platform === 'ios' ? 'simulator' : 'emulator';
      it(`opens an ${platform} project in a ${runtime} (dev client: ${isDevClient})`, async () => {
        const devServer = await getRunningServer();
        devServer.isDevClient = isDevClient;
        const { url } = await devServer.openPlatformAsync(runtime);

        expect(
          (await devServer['getPlatformManagerAsync'](runtime)).openAsync
        ).toHaveBeenNthCalledWith(1, { runtime: isDevClient ? 'custom' : 'expo' }, {});

        expect(url).toBe(platform === 'ios' ? 'mock-apple-url' : 'mock-android-url');
      });
    }
  }
});

describe('stopAsync', () => {
  it(`stops a running dev server`, async () => {
    const server = new MockBundlerDevServer('/', getPlatformBundlers({}));
    const instance = await server.startAsync({
      location: {
        hostType: 'tunnel',
      },
    });
    const ngrok = server.getNgrok();
    const devSession = server.getNgrok();

    // Ensure services were started.
    expect(ngrok.startAsync).toHaveBeenCalled();
    expect(devSession.startAsync).toHaveBeenCalled();

    // Invoke the stop function
    await server.stopAsync();

    // Ensure services were stopped.
    expect(instance.server.close).toHaveBeenCalled();
    expect(ngrok.stopAsync).toHaveBeenCalled();
    expect(devSession.stopAsync).toHaveBeenCalled();
    expect(server.getInstance()).toBeNull();
  });
});

describe('getExpoGoUrl', () => {
  it(`gets the interstitial page URL`, async () => {
    vol.fromJSON(
      {
        'node_modules/expo-dev-launcher/package.json': '',
      },
      '/'
    );

    const server = new MockBundlerDevServer('/', getPlatformBundlers({}));
    await server.startAsync({
      location: {},
    });

    const urlCreator = server.getPublicUrlCreator();
    urlCreator.constructLoadingUrl = jest.fn(urlCreator.constructLoadingUrl);

    expect(server.getExpoGoUrl('emulator', true)).toBe(
      'http://100.100.1.100:3000/_expo/loading?platform=android'
    );
    expect(server.getExpoGoUrl('simulator', true)).toBe(
      'http://100.100.1.100:3000/_expo/loading?platform=ios'
    );
    expect(server.getExpoGoUrl(null, true)).toBe('http://100.100.1.100:3000/_expo/loading');
    expect(urlCreator.constructLoadingUrl).toBeCalledTimes(3);

    // should skip interstitial page if no development build is installed on the device
    expect(server.getExpoGoUrl('emulator', false)).toBe('exp://100.100.1.100:3000');
    expect(server.getExpoGoUrl('simulator', false)).toBe('exp://100.100.1.100:3000');
    expect(Log.warn).toHaveBeenCalledTimes(2);
  });
  it(`gets the native Expo Go URL`, async () => {
    const server = new MockBundlerDevServer('/', getPlatformBundlers({}));
    await server.startAsync({
      location: {},
    });

    expect(await server.getExpoGoUrl('emulator', true)).toBe('exp://100.100.1.100:3000');
    expect(await server.getExpoGoUrl('simulator', true)).toBe('exp://100.100.1.100:3000');
  });
});

describe('getNativeRuntimeUrl', () => {
  it(`gets the native runtime URL`, async () => {
    const server = new MockBundlerDevServer('/', getPlatformBundlers({}));
    await server.startAsync({
      location: {},
    });
    expect(server.getNativeRuntimeUrl()).toBe('exp://100.100.1.100:3000');
    expect(server.getNativeRuntimeUrl({ hostname: 'localhost' })).toBe('exp://127.0.0.1:3000');
    expect(server.getNativeRuntimeUrl({ scheme: 'foobar' })).toBe('exp://100.100.1.100:3000');
  });
  it(`gets the native runtime URL for dev client`, async () => {
    const server = new MockBundlerDevServer('/', getPlatformBundlers({}), true);
    await server.startAsync({
      location: {
        scheme: 'my-app',
      },
    });
    expect(server.getNativeRuntimeUrl()).toBe(
      'my-app://expo-development-client/?url=http%3A%2F%2F100.100.1.100%3A3000'
    );
    expect(server.getNativeRuntimeUrl({ hostname: 'localhost' })).toBe(
      'my-app://expo-development-client/?url=http%3A%2F%2F127.0.0.1%3A3000'
    );
    expect(server.getNativeRuntimeUrl({ scheme: 'foobar' })).toBe(
      'foobar://expo-development-client/?url=http%3A%2F%2F100.100.1.100%3A3000'
    );
  });
});

describe('getManifestMiddlewareAsync', () => {
  const server = new MockBundlerDevServer('/', getPlatformBundlers({}));
  it(`asserts invalid manifest type`, async () => {
    await expect(
      server['getManifestMiddlewareAsync']({
        // @ts-expect-error
        forceManifestType: 'foobar',
      })
    ).rejects.toThrow(/Manifest middleware for type 'foobar' not found/);
  });
  it(`asserts server is not running`, async () => {
    await expect(server['getManifestMiddlewareAsync']()).rejects.toThrow(
      /Dev server instance not found/
    );
  });
});

describe('_startTunnelAsync', () => {
  const server = new MockBundlerDevServer('/', getPlatformBundlers({}));
  it(`returns null when the server isn't running`, async () => {
    expect(await server._startTunnelAsync()).toEqual(null);
  });
});
