// Copyright 2019-present 650 Industries. All rights reserved.

#import <ABI45_0_0EXNotifications/ABI45_0_0EXUserFacingNotificationsPermissionsRequester.h>
#import <ABI45_0_0ExpoModulesCore/ABI45_0_0EXDefines.h>
#import <UserNotifications/UserNotifications.h>

@interface ABI45_0_0EXUserFacingNotificationsPermissionsRequester ()

@property (nonatomic, assign) dispatch_queue_t methodQueue;

@end

@implementation ABI45_0_0EXUserFacingNotificationsPermissionsRequester

static NSDictionary *_requestedPermissions;

+ (NSString *)permissionType
{
  return @"userFacingNotifications";
}

- (instancetype)initWithMethodQueue:(dispatch_queue_t)methodQueue
{
  if (self = [super init]) {
    _methodQueue = methodQueue;
  }
  return self;
}

- (NSDictionary *)getPermissions
{
  dispatch_assert_queue_not(dispatch_get_main_queue());
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);

  __block NSMutableDictionary *status = [NSMutableDictionary dictionary];
  __block ABI45_0_0EXPermissionStatus generalStatus = ABI45_0_0EXPermissionStatusUndetermined;

  [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
    if (settings.authorizationStatus == UNAuthorizationStatusAuthorized) {
      generalStatus = ABI45_0_0EXPermissionStatusGranted;
    } else if (settings.authorizationStatus == UNAuthorizationStatusDenied) {
      generalStatus = ABI45_0_0EXPermissionStatusDenied;
    }

    status[@"status"] = [self authorizationStatusToEnum:settings.authorizationStatus];

    status[@"allowsDisplayInNotificationCenter"] = [self notificationSettingToNumber:settings.notificationCenterSetting] ?: [NSNull null];
    status[@"allowsDisplayOnLockScreen"] = [self notificationSettingToNumber:settings.lockScreenSetting] ?: [NSNull null];
    status[@"allowsDisplayInCarPlay"] = [self notificationSettingToNumber:settings.carPlaySetting] ?: [NSNull null];

    status[@"allowsAlert"] = [self notificationSettingToNumber:settings.alertSetting] ?: [NSNull null];
    status[@"allowsBadge"] = [self notificationSettingToNumber:settings.badgeSetting] ?: [NSNull null];
    status[@"allowsSound"] = [self notificationSettingToNumber:settings.soundSetting] ?: [NSNull null];

    if (@available(iOS 12.0, *)) {
      status[@"allowsCriticalAlerts"] = [self notificationSettingToNumber:settings.criticalAlertSetting] ?: [NSNull null];
    }

    status[@"alertStyle"] = [self alertStyleToEnum:settings.alertStyle];
    status[@"allowsPreviews"] = [self showPreviewsSettingToEnum:settings.showPreviewsSetting];
    if (@available(iOS 12.0, *)) {
      status[@"providesAppNotificationSettings"] = @(settings.providesAppNotificationSettings);
    }

    if (@available(iOS 13.0, *)) {
      status[@"allowsAnnouncements"] = [self notificationSettingToNumber:settings.announcementSetting] ?: [NSNull null];
    }

    dispatch_semaphore_signal(sem);
  }];

  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

  return @{
           @"status": @(generalStatus),
           @"ios": status
           };
}

- (void)requestPermissionsWithResolver:(ABI45_0_0EXPromiseResolveBlock)resolve rejecter:(ABI45_0_0EXPromiseRejectBlock)reject
{
  if (!_requestedPermissions || [_requestedPermissions count] == 0) {
    _requestedPermissions = @{
                              @"allowAlert": @(YES),
                              @"allowBadge": @(YES),
                              @"allowSound": @(YES)
                            };
  }
  [self requestPermissions:_requestedPermissions withResolver:resolve rejecter:reject];
}

- (void)requestPermissions:(NSDictionary *)permissions withResolver:(ABI45_0_0EXPromiseResolveBlock)resolve rejecter:(ABI45_0_0EXPromiseRejectBlock)reject
{
  UNAuthorizationOptions options = UNAuthorizationOptionNone;
  if ([permissions[@"allowAlert"] boolValue]) {
    options |= UNAuthorizationOptionAlert;
  }
  if ([permissions[@"allowBadge"] boolValue]) {
    options |= UNAuthorizationOptionBadge;
  }
  if ([permissions[@"allowSound"] boolValue]) {
    options |= UNAuthorizationOptionSound;
  }
  if ([permissions[@"allowDisplayInCarPlay"] boolValue]) {
    options |= UNAuthorizationOptionCarPlay;
  }
  if (@available(iOS 12.0, *)) {
    if ([permissions[@"allowCriticalAlerts"] boolValue]) {
        options |= UNAuthorizationOptionCriticalAlert;
    }
    if ([permissions[@"provideAppNotificationSettings"] boolValue]) {
        options |= UNAuthorizationOptionProvidesAppNotificationSettings;
    }
    if ([permissions[@"allowProvisional"] boolValue]) {
        options |= UNAuthorizationOptionProvisional;
    }
  }
  if (@available(iOS 13.0, *)) {
    if ([permissions[@"allowAnnouncements"] boolValue]) {
      options |= UNAuthorizationOptionAnnouncement;
    }
  }
  [self requestAuthorizationOptions:options withResolver:resolve rejecter:reject];
}

- (void)requestAuthorizationOptions:(UNAuthorizationOptions)options withResolver:(ABI45_0_0EXPromiseResolveBlock)resolve rejecter:(ABI45_0_0EXPromiseRejectBlock)reject
{
  ABI45_0_0EX_WEAKIFY(self);
  [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError * _Nullable error) {
    ABI45_0_0EX_STRONGIFY(self);
    // getPermissions blocks method queue on which this callback is being executed
    // so we have to dispatch to another queue.
    dispatch_async(self.methodQueue, ^{
      if (error) {
        reject(@"ERR_PERMISSIONS_REQUEST_NOTIFICATIONS", error.description, error);
      } else {
        resolve([self getPermissions]);
      }
    });
  }];
}

# pragma mark - Utilities - notification settings to string

- (NSNumber *)showPreviewsSettingToEnum:(UNShowPreviewsSetting)setting {
  switch (setting) {
    case UNShowPreviewsSettingNever:
      return @(0);
    case UNShowPreviewsSettingAlways:
      return @(1);
    case UNShowPreviewsSettingWhenAuthenticated:
      return @(2);
  }
}

- (NSNumber *)alertStyleToEnum:(UNAlertStyle)style {
  switch (style) {
    case UNAlertStyleNone:
      return @(0);
    case UNAlertStyleBanner:
      return @(1);
    case UNAlertStyleAlert:
      return @(2);
  }
}

- (NSNumber *)authorizationStatusToEnum:(UNAuthorizationStatus)status
{
  switch (status) {
    case UNAuthorizationStatusNotDetermined:
      return @(0);
    case UNAuthorizationStatusDenied:
      return @(1);
    case UNAuthorizationStatusAuthorized:
      return @(2);
    case UNAuthorizationStatusProvisional:
      return @(3);
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
    case UNAuthorizationStatusEphemeral:
      return @(4);
#endif
  }
}

- (nullable NSNumber *)notificationSettingToNumber:(UNNotificationSetting)setting
{
  switch (setting) {
    case UNNotificationSettingEnabled:
      return @(YES);
    case UNNotificationSettingDisabled:
      return @(NO);
    case UNNotificationSettingNotSupported:
      return nil;
  }
}

+ (void)setRequestedPermissions:(NSDictionary *)permissions
{
  _requestedPermissions = permissions;
}

@end
