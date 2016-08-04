//
//  CBLJSListFunctionCompiler.m
//  CouchbaseLite
//
//  Created by Igor Evsukov on 8/4/13.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//

#import "CBLJSListFunctionCompiler.h"
#import "CBLQuery.h"
#import "CouchbaseLitePrivate.h"
#import "CBLFunctionResult.h"
#import <JavaScriptCore/JavaScript.h>
#import <JavaScriptCore/JSStringRefCF.h>

/* NOTE: JavaScriptCore is not a public system framework on iOS, so you'll need to link your iOS app
 with your own copy of it. See <https://github.com/phoboslab/JavaScriptCore-iOS>. */

/* NOTE: This source file requires ARC. */

@implementation CBLJSListFunctionCompiler

static NSString* const kCBLCurrentFunctionResultKey = @"FunctionResult";
static NSString* const kCBLCurrentGetRowBlockKey = @"GetRowBlock";

// This is the body of the JavaScript "getRow()" function.
static JSValueRef GetRowCallback(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject,
                                 size_t argumentCount, const JSValueRef arguments[],
                                 JSValueRef* exception)
{
    CBLListFunctionGetRowBlock getRowBlock = NSThread.currentThread.threadDictionary[kCBLCurrentGetRowBlockKey];
    if (!getRowBlock)
        return JSValueMakeUndefined(ctx);
    
    CBLQueryRow *row = getRowBlock();
    JSValueRef ret = CBLNSObjectToJSValueRef(ctx, [row asJSValue]);
    return ret;
}

// This is the body of the JavaScript "start()" function.
static JSValueRef StartCallback(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject,
                                 size_t argumentCount, const JSValueRef arguments[],
                                 JSValueRef* exception)
{
    CBLFunctionResult* currentFunctionResult = NSThread.currentThread.threadDictionary[kCBLCurrentFunctionResultKey];
    // by this we're limiting start() to be only called once
    if (!currentFunctionResult && argumentCount > 0) {
        NSDictionary* startDict = (NSDictionary*)CBLJSValueToNSObject(ctx, arguments[0]);
        currentFunctionResult = [[CBLFunctionResult alloc] initWithResultObject: startDict];
        NSThread.currentThread.threadDictionary[kCBLCurrentFunctionResultKey] = currentFunctionResult;
    }
    
    return JSValueMakeUndefined(ctx);
}

// This is the body of the JavaScript "send()" function.
static JSValueRef SendCallback(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject,
                                size_t argumentCount, const JSValueRef arguments[],
                                JSValueRef* exception)
{
    if (argumentCount > 0) {
        NSString* chunk = (NSString*)CBLJSValueToNSObject(ctx, arguments[0]);
        
        CBLFunctionResult* currentFunctionResult = NSThread.currentThread.threadDictionary[kCBLCurrentFunctionResultKey];
        if (!currentFunctionResult) {
            currentFunctionResult = [[CBLFunctionResult alloc] initWithResultObject: chunk];
            NSThread.currentThread.threadDictionary[kCBLCurrentFunctionResultKey] = currentFunctionResult;
        } else {
            // check if it's actually a string
            [currentFunctionResult appendChunkToBody: chunk];
        }
    }
    return JSValueMakeUndefined(ctx);
}

- (instancetype) initWithJSGlobalContextRef: (JSGlobalContextRef)context {
    self = [super initWithJSGlobalContextRef: context];
    if (self) {
        JSGlobalContextRef context = self.context;
        // Install the "getRow" function in the context's namespace:
        JSStringRef getRowName = JSStringCreateWithCFString(CFSTR("getRow"));
        JSObjectRef getRowFn = JSObjectMakeFunctionWithCallback(context, getRowName, &GetRowCallback);
        JSObjectSetProperty(context, JSContextGetGlobalObject(context),
                            getRowName, getRowFn,
                            kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete,
                            NULL);
        JSStringRelease(getRowName);
        
        // Installing "start" function in the context's namespace:
        JSStringRef startName = JSStringCreateWithCFString(CFSTR("start"));
        JSObjectRef startFn = JSObjectMakeFunctionWithCallback(context, startName, &StartCallback);
        JSObjectSetProperty(context, JSContextGetGlobalObject(context),
                            startName, startFn,
                            kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete,
                            NULL);
        JSStringRelease(startName);
        
        // Installing "start" function in the context's namespace:
        JSStringRef sendName = JSStringCreateWithCFString(CFSTR("send"));
        JSObjectRef sendFn = JSObjectMakeFunctionWithCallback(context, sendName, &SendCallback);
        JSObjectSetProperty(context, JSContextGetGlobalObject(context),
                            sendName, sendFn,
                            kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete,
                            NULL);
        JSStringRelease(sendName);
    }
    return self;
}


- (CBLListFunctionBlock) compileListFunction: (NSString*)listName source: (NSString*)listSource userInfo: (NSDictionary*)userInfo {
    // Compile the function:
    CBLJSFunction* fn = [[CBLJSFunction alloc] initWithCompiler: self
                                                     sourceCode: listSource
                                                   sourceFiname: listName
                                                     paramNames: @[@"head", @"req"]
                                                 requireContext: userInfo];
    if (!fn)
        return nil;
    
    JSContextRef ctx = self.context;
    CBLListFunctionBlock block = ^CBLFunctionResult*(NSDictionary *head, NSDictionary *params, CBLListFunctionGetRowBlock getRowBlock) {
        CBLFunctionResult* result = nil;
        
        [NSThread.currentThread.threadDictionary setValue:getRowBlock forKey:kCBLCurrentGetRowBlockKey];
        JSValueRef exception = NULL;
        //CFAbsoluteTime start1 = CFAbsoluteTimeGetCurrent();
        JSValueRef fnRes = [fn callWithParams:@[head ? head : NSNull.null, params ? params : NSNull.null] exception:&exception];
        //CFAbsoluteTime end1 = CFAbsoluteTimeGetCurrent();
        if (NSThread.currentThread.threadDictionary[kCBLCurrentFunctionResultKey]) {
            result = NSThread.currentThread.threadDictionary[kCBLCurrentFunctionResultKey];
            [NSThread.currentThread.threadDictionary removeObjectForKey:kCBLCurrentFunctionResultKey];
        }
        [NSThread.currentThread.threadDictionary removeObjectForKey:kCBLCurrentGetRowBlockKey];
        
        //CFAbsoluteTime start2 = CFAbsoluteTimeGetCurrent();
        id obj = CBLJSValueToNSObject(ctx, fnRes);
        //CFAbsoluteTime end2 = CFAbsoluteTimeGetCurrent();
        
        //LogTo(List, @"func %3.3fsecs, ret conversion %3.3fsecs", (end1 - start1), (end2 - start2));
        
        if (exception) {
            result = [CBLFunctionResult new];
            
            NSMutableDictionary *body = [NSMutableDictionary dictionary];
            
            JSStringRef error = JSValueToStringCopy(ctx, exception, NULL);
            CFStringRef cfError = error ? JSStringCopyCFString(NULL, error) : NULL;
            [body setValue:(__bridge id)cfError forKey:@"error"];
            CFRelease(cfError);
            
            [body setValue:obj forKey:@"result"];
            result.body = body;
            result.status = kCBLStatusException;
        } else if ([obj isKindOfClass:[NSString class]]) {
            if (!result)
                result = [[CBLFunctionResult alloc] initWithResultObject: obj];
            else
                [result appendChunkToBody:obj];
        } else if ([obj isKindOfClass:[NSDictionary class]]) { // optimization, vanilla couchdb doesn't support response object for list functions
            result = [[CBLFunctionResult alloc] initWithResultObject: obj];
        }
        
        return result;
    };
    return [block copy];
}

@end
