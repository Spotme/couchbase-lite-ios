//
//  CBLJSFunction.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/28/13.
//
//

#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

extern void WarnJSException(JSContextRef context, NSString* warning, JSValueRef exception);

extern NSString* const kCBLJSFunctionCurrentRequireContextKey;

extern NSString*  CBLJSValueToNSString   ( JSContextRef ctx, JSValueRef v );
extern JSValueRef CBLNSObjectToJSValueRef( JSContextRef ctx, NSObject *obj );
extern NSObject*  CBLJSValueToNSObject   ( JSContextRef ctx, JSValueRef value );
extern JSValue*   CBLJSValueFromJSONData ( JSContext* context, NSData* json);


/** Abstract base class for JavaScript-based CBL*Compilers */
@interface CBLJSCompiler : NSObject

- (instancetype) initWithJSGlobalContextRef: (JSGlobalContextRef)context NS_DESIGNATED_INITIALIZER;

@property (readonly) JSGlobalContextRef context;
@end


/** Wrapper for a compiled JavaScript function. */
@interface CBLJSFunction : NSObject

- (instancetype) initWithCompiler: (CBLJSCompiler*)compiler
                       sourceCode: (NSString*)source
                       paramNames: (NSArray*)paramNames;

- (instancetype) initWithCompiler: (CBLJSCompiler*)compiler
                       sourceCode: (NSString*)source
                       paramNames: (NSArray*)paramNames
                   requireContext: (NSDictionary*)requireContext;

@property (readonly) NSDictionary* requireContext;

- (JSValueRef) call: (id)param1, ...;

- (JSValueRef) callWithParams: (NSArray*)params exception:(JSValueRef*)outException;

@end
