/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ABI45_0_0RCTComponentViewFactory.h"

#import <ABI45_0_0React/ABI45_0_0RCTAssert.h>
#import <ABI45_0_0React/ABI45_0_0RCTConversions.h>

#import <butter/map.h>
#import <butter/mutex.h>
#import <butter/set.h>

#import <ABI45_0_0React/ABI45_0_0renderer/componentregistry/ComponentDescriptorProviderRegistry.h>
#import <ABI45_0_0React/ABI45_0_0renderer/componentregistry/componentNameByABI45_0_0ReactViewName.h>
#import <ABI45_0_0React/ABI45_0_0renderer/componentregistry/native/NativeComponentRegistryBinding.h>
#import <ABI45_0_0React/ABI45_0_0renderer/core/PropsParserContext.h>
#import <ABI45_0_0React/ABI45_0_0renderer/core/ABI45_0_0ReactPrimitives.h>

#ifdef ABI45_0_0RN_DISABLE_OSS_PLUGIN_HEADER
#import <ABI45_0_0RCTFabricComponentPlugin/ABI45_0_0RCTFabricPluginProvider.h>
#else
#import "ABI45_0_0RCTFabricComponentsPlugins.h"
#endif

#import "ABI45_0_0RCTComponentViewClassDescriptor.h"
#import "ABI45_0_0RCTFabricComponentsPlugins.h"
#import "ABI45_0_0RCTImageComponentView.h"
#import "ABI45_0_0RCTLegacyViewManagerInteropComponentView.h"
#import "ABI45_0_0RCTMountingTransactionObserving.h"
#import "ABI45_0_0RCTParagraphComponentView.h"
#import "ABI45_0_0RCTRootComponentView.h"
#import "ABI45_0_0RCTTextInputComponentView.h"
#import "ABI45_0_0RCTUnimplementedViewComponentView.h"
#import "ABI45_0_0RCTViewComponentView.h"

#import <objc/runtime.h>

using namespace ABI45_0_0facebook::ABI45_0_0React;

// Allow JS runtime to register native components as needed. For static view configs.
void ABI45_0_0RCTInstallNativeComponentRegistryBinding(ABI45_0_0facebook::jsi::Runtime &runtime)
{
  auto hasComponentProvider = [](std::string const &name) -> bool {
    return [[ABI45_0_0RCTComponentViewFactory currentComponentViewFactory]
        registerComponentIfPossible:componentNameByABI45_0_0ReactViewName(name)];
  };
  NativeComponentRegistryBinding::install(runtime, std::move(hasComponentProvider));
}

static Class<ABI45_0_0RCTComponentViewProtocol> ABI45_0_0RCTComponentViewClassWithName(const char *componentName)
{
  return ABI45_0_0RCTFabricComponentsProvider(componentName);
}

@implementation ABI45_0_0RCTComponentViewFactory {
  butter::map<ComponentHandle, ABI45_0_0RCTComponentViewClassDescriptor> _componentViewClasses;
  butter::set<std::string> _registeredComponentsNames;
  ComponentDescriptorProviderRegistry _providerRegistry;
  butter::shared_mutex _mutex;
}

+ (ABI45_0_0RCTComponentViewFactory *)currentComponentViewFactory
{
  static dispatch_once_t onceToken;
  static ABI45_0_0RCTComponentViewFactory *componentViewFactory;

  dispatch_once(&onceToken, ^{
    componentViewFactory = [ABI45_0_0RCTComponentViewFactory new];
    [componentViewFactory registerComponentViewClass:[ABI45_0_0RCTRootComponentView class]];
    [componentViewFactory registerComponentViewClass:[ABI45_0_0RCTViewComponentView class]];
    [componentViewFactory registerComponentViewClass:[ABI45_0_0RCTParagraphComponentView class]];
    [componentViewFactory registerComponentViewClass:[ABI45_0_0RCTTextInputComponentView class]];

    Class<ABI45_0_0RCTComponentViewProtocol> imageClass = ABI45_0_0RCTComponentViewClassWithName("Image");
    [componentViewFactory registerComponentViewClass:imageClass];

    componentViewFactory->_providerRegistry.setComponentDescriptorProviderRequest(
        [](ComponentName requestedComponentName) {
          [componentViewFactory registerComponentIfPossible:requestedComponentName];
        });
  });

  return componentViewFactory;
}

- (ABI45_0_0RCTComponentViewClassDescriptor)_componentViewClassDescriptorFromClass:(Class<ABI45_0_0RCTComponentViewProtocol>)viewClass
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
  return ABI45_0_0RCTComponentViewClassDescriptor
  {
    .viewClass = viewClass,
    .observesMountingTransactionWillMount =
        (bool)class_respondsToSelector(viewClass, @selector(mountingTransactionWillMountWithMetadata:)),
    .observesMountingTransactionDidMount =
        (bool)class_respondsToSelector(viewClass, @selector(mountingTransactionDidMountWithMetadata:)),
  };
#pragma clang diagnostic pop
}

- (BOOL)registerComponentIfPossible:(std::string const &)name
{
  if (_registeredComponentsNames.find(name) != _registeredComponentsNames.end()) {
    // Component has already been registered.
    return YES;
  }

  // Fallback 1: Call provider function for component view class.
  Class<ABI45_0_0RCTComponentViewProtocol> klass = ABI45_0_0RCTComponentViewClassWithName(name.c_str());
  if (klass) {
    [self registerComponentViewClass:klass];
    return YES;
  }

  // Fallback 2: Try to use Paper Interop.
  if ([ABI45_0_0RCTLegacyViewManagerInteropComponentView isSupported:ABI45_0_0RCTNSStringFromString(name)]) {
    auto flavor = std::make_shared<std::string const>(name);
    auto componentName = ComponentName{flavor->c_str()};
    auto componentHandle = reinterpret_cast<ComponentHandle>(componentName);
    auto constructor = [ABI45_0_0RCTLegacyViewManagerInteropComponentView componentDescriptorProvider].constructor;

    [self _addDescriptorToProviderRegistry:ComponentDescriptorProvider{
                                               componentHandle, componentName, flavor, constructor}];

    _componentViewClasses[componentHandle] =
        [self _componentViewClassDescriptorFromClass:[ABI45_0_0RCTLegacyViewManagerInteropComponentView class]];
    return YES;
  }

  // Fallback 3: use <UnimplementedView> if component doesn't exist.
  auto flavor = std::make_shared<std::string const>(name);
  auto componentName = ComponentName{flavor->c_str()};
  auto componentHandle = reinterpret_cast<ComponentHandle>(componentName);
  auto constructor = [ABI45_0_0RCTUnimplementedViewComponentView componentDescriptorProvider].constructor;

  [self _addDescriptorToProviderRegistry:ComponentDescriptorProvider{
                                             componentHandle, componentName, flavor, constructor}];

  _componentViewClasses[componentHandle] =
      [self _componentViewClassDescriptorFromClass:[ABI45_0_0RCTUnimplementedViewComponentView class]];

  // No matching class exists for `name`.
  return NO;
}

- (void)registerComponentViewClass:(Class<ABI45_0_0RCTComponentViewProtocol>)componentViewClass
{
  ABI45_0_0RCTAssert(componentViewClass, @"ABI45_0_0RCTComponentViewFactory: Provided `componentViewClass` is `nil`.");
  std::unique_lock<butter::shared_mutex> lock(_mutex);

  auto componentDescriptorProvider = [componentViewClass componentDescriptorProvider];
  _componentViewClasses[componentDescriptorProvider.handle] =
      [self _componentViewClassDescriptorFromClass:componentViewClass];
  [self _addDescriptorToProviderRegistry:componentDescriptorProvider];

  auto supplementalComponentDescriptorProviders = [componentViewClass supplementalComponentDescriptorProviders];
  for (const auto &provider : supplementalComponentDescriptorProviders) {
    [self _addDescriptorToProviderRegistry:provider];
  }
}

- (void)_addDescriptorToProviderRegistry:(ComponentDescriptorProvider const &)provider
{
  _registeredComponentsNames.insert(provider.name);
  _providerRegistry.add(provider);
}

- (ABI45_0_0RCTComponentViewDescriptor)createComponentViewWithComponentHandle:(ABI45_0_0facebook::ABI45_0_0React::ComponentHandle)componentHandle
{
  ABI45_0_0RCTAssertMainQueue();
  std::shared_lock<butter::shared_mutex> lock(_mutex);

  auto iterator = _componentViewClasses.find(componentHandle);
  ABI45_0_0RCTAssert(
      iterator != _componentViewClasses.end(),
      @"ComponentView with componentHandle `%lli` (`%s`) not found.",
      componentHandle,
      (char *)componentHandle);
  auto componentViewClassDescriptor = iterator->second;
  Class viewClass = componentViewClassDescriptor.viewClass;

  return ABI45_0_0RCTComponentViewDescriptor{
      .view = [viewClass new],
      .observesMountingTransactionWillMount = componentViewClassDescriptor.observesMountingTransactionWillMount,
      .observesMountingTransactionDidMount = componentViewClassDescriptor.observesMountingTransactionDidMount,
  };
}

- (ABI45_0_0facebook::ABI45_0_0React::ComponentDescriptorRegistry::Shared)createComponentDescriptorRegistryWithParameters:
    (ABI45_0_0facebook::ABI45_0_0React::ComponentDescriptorParameters)parameters
{
  std::shared_lock<butter::shared_mutex> lock(_mutex);

  return _providerRegistry.createComponentDescriptorRegistry(parameters);
}

@end
