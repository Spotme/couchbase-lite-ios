//
//  CBLJSFunction.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/28/13.
//
//

#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScript.h>

// extern JSValueRef IDToValue(JSContextRef ctx, id object);
// extern id ValueToID(JSContextRef ctx, JSValueRef value);
extern void WarnJSException(JSContextRef context, NSString* warning, JSValueRef exception);

extern NSString* const kCBLJSFunctionCurrentRequireContextKey;

// from https://github.com/phoboslab/Ejecta/blob/master/Source/Ejecta/EJConvert.h
NSString *JSValueToNSString( JSContextRef ctx, JSValueRef v );
JSValueRef NSStringToJSValue( JSContextRef ctx, NSString *string );
void JSValueUnprotectSafe( JSContextRef ctx, JSValueRef v );
JSValueRef NSObjectToJSValue( JSContextRef ctx, NSObject *obj );
NSObject *JSValueToNSObject( JSContextRef ctx, JSValueRef value );
// * * *

/** Abstract base class for JavaScript-based CBL*Compilers */
@interface CBLJSCompiler : NSObject
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
