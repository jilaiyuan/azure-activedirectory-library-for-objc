// Copyright (c) Microsoft Corporation.
// All rights reserved.
//
// This code is licensed under the MIT License.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "ADWebAuthController+Internal.h"
#import "ADUserIdentifier.h"
#import "ADAuthenticationContext+Internal.h"
#import "MSIDNotifications.h"
#import "NSDictionary+MSIDExtensions.h"
#import "ADAuthenticationSettings.h"

/*! Fired at the start of a resource load in the webview. */
NSString* ADWebAuthDidStartLoadNotification = @"ADWebAuthDidStartLoadNotification";

/*! Fired when a resource finishes loading in the webview. */
NSString* ADWebAuthDidFinishLoadNotification = @"ADWebAuthDidFinishLoadNotification";

/*! Fired when web authentication fails due to reasons originating from the network. */
NSString* ADWebAuthDidFailNotification = @"ADWebAuthDidFailNotification";

/*! Fired when authentication finishes */
NSString* ADWebAuthDidCompleteNotification = @"ADWebAuthDidCompleteNotification";

NSString* ADWebAuthDidReceieveResponseFromBroker = @"ADWebAuthDidReceiveResponseFromBroker";

NSString* ADWebAuthWillSwitchToBrokerApp = @"ADWebAuthWillSwitchToBrokerApp";

// Private interface declaration
@interface ADWebAuthController ()
@end

// Implementation
@implementation ADWebAuthController

#pragma mark - Initialization

+ (void)cancelCurrentWebAuthSession
{
    [MSIDWebviewAuthorization cancelCurrentSession];
}

#if TARGET_OS_IPHONE
static ADAuthenticationResult *s_result = nil;

+ (ADAuthenticationResult *)responseFromInterruptedBrokerSession
{
    ADAuthenticationResult *result = s_result;
    s_result = nil;
    return result;
}
#endif // TARGET_OS_IPHONE
@end

#pragma mark - Private Methods

@implementation ADWebAuthController (Internal)

+ (void)registerWebAuthNotifications
{
    MSIDNotifications.webAuthDidCompleteNotificationName = ADWebAuthDidCompleteNotification;
    MSIDNotifications.webAuthDidFailNotificationName = ADWebAuthDidFailNotification;
    MSIDNotifications.webAuthDidStartLoadNotificationName = ADWebAuthDidStartLoadNotification;
    MSIDNotifications.webAuthDidFinishLoadNotificationName = ADWebAuthDidFinishLoadNotification;
}

+ (void)startWithRequest:(ADRequestParameters *)requestParams
          promptBehavior:(ADPromptBehavior)promptBehavior
                 context:(ADAuthenticationContext *)context
              completion:(MSIDWebviewAuthCompletionHandler)completionHandler
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self registerWebAuthNotifications];
    });
    
    //TODO: Replace with MSIDAADEndpointProvider method once available
    NSString *authorityWithOAuthSuffix = [NSString stringWithFormat:@"%@%@", context.authority, MSID_OAUTH2_AUTHORIZE_SUFFIX];
    
    MSIDWebviewConfiguration *webviewConfig = [[MSIDWebviewConfiguration alloc] initWithAuthorizationEndpoint:[NSURL URLWithString:authorityWithOAuthSuffix]
                                                                                                  redirectUri:requestParams.redirectUri
                                                                                                     clientId:requestParams.clientId
                                                                                                     resource:requestParams.resource
                                                                                                       scopes:nil
                                                                                                correlationId:requestParams.correlationId
                                                                                                   enablePkce:NO];
    webviewConfig.ignoreInvalidState = YES;

    webviewConfig.loginHint = requestParams.identifier.userId;
    webviewConfig.promptBehavior = [ADAuthenticationContext getPromptParameter:promptBehavior];
    
    webviewConfig.extraQueryParameters = [self.class dictionaryFromQueryString:requestParams.extraQueryParameters];
    
    if (requestParams.claims)
    {
        webviewConfig.claims = [requestParams.claims msidWWWFormURLDecode];
    }

#if TARGET_OS_IPHONE
    webviewConfig.parentController = context.parentController;
    webviewConfig.presentationType = ADAuthenticationSettings.sharedInstance.webviewPresentationStyle;
#endif

    [MSIDWebviewAuthorization startEmbeddedWebviewAuthWithConfiguration:webviewConfig
                                                          oauth2Factory:context.oauthFactory
                                                                webview:context.webView
                                                                context:requestParams
                                                      completionHandler:completionHandler];
}

//TODO: Replace with MSID utility
+ (NSDictionary *)dictionaryFromQueryString:(NSString *)string
{
    if ([NSString msidIsStringNilOrBlank:string])
    {
        return nil;
    }
    
    NSArray *queries = [string componentsSeparatedByString:@"&"];
    NSMutableDictionary *queryDict = [NSMutableDictionary new];
    
    for (NSString *query in queries)
    {
        NSArray *queryElements = [query componentsSeparatedByString:@"="];
        if (queryElements.count > 2)
        {
            MSID_LOG_WARN(nil, @"Query parameter must be a form key=value: %@", query);
            continue;
        }
        
        NSString *key = [queryElements[0] msidTrimmedString];
        if ([NSString msidIsStringNilOrBlank:key])
        {
            MSID_LOG_WARN(nil, @"Query parameter must have a key");
            continue;
        }
        
        NSString *value = @"";
        if (queryElements.count == 2)
        {
            value = [queryElements[1] msidTrimmedString];
        }
        
        [queryDict setValue:value forKey:key];
    }
    
    return queryDict;
}


#if TARGET_OS_IPHONE
+ (void)setInterruptedBrokerResult:(ADAuthenticationResult *)result
{
    s_result = result;
}
#endif // TARGET_OS_IPHONE

@end
