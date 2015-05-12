//
//  CBLJSFunction.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/28/13.
//
//

#import "CBLJSFunction.h"
#import <JavaScriptCore/JavaScript.h>
#import <JavaScriptCore/JSStringRefCF.h>
#import "Logging.h"

/* NOTE: JavaScriptCore is not a public system framework on iOS, so you'll need to link your iOS app
   with your own copy of it. See <https://github.com/phoboslab/JavaScriptCore-iOS>. */

/* NOTE: This source file requires ARC. */

NSString* const kCBLJSFunctionCurrentRequireContextKey = @"kCBLJSFunctionCurrentRequireContext";

#pragma mark - JS COMPILER
// This is the body of the JavaScript "require()" function.
static JSValueRef RequireCallback(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject,
                                  size_t argumentCount, const JSValueRef arguments[],
                                  JSValueRef* exception)
{
    if (argumentCount < 1)
        return JSValueMakeUndefined(ctx);
    
    NSDictionary* currentRequireContext = NSThread.currentThread.threadDictionary[kCBLJSFunctionCurrentRequireContextKey];
    
    NSString* moduleName = (NSString*)JSValueToNSObject/*ValueToID*/(ctx, arguments[0]);
    if (!moduleName || ![moduleName isKindOfClass: [NSString class]])
        return JSValueMakeUndefined(ctx);
    
    // module name is expected as lib/foo/bar, so what we're going to do here
    // is to replace / with . and use valueForKeyPath: to perform module code lookup
    
    // safety first, if first char is @ valueForKeyPath: will treat is as built-in function like @sum
    if ([moduleName hasPrefix:@"@"])
        moduleName = [moduleName substringFromIndex: 1];
    
    // FIXME: evil hack to fix my project
    if ([moduleName hasPrefix:@"./"])
        moduleName = [NSString stringWithFormat: @"lib/%@", [moduleName substringFromIndex: 2]];
    
    // if there's a . in filename – then we obviously screwed
    NSString* moduleLookupKeyPath = [moduleName stringByReplacingOccurrencesOfString: @"/" withString: @"."];
    
    NSString* moduleSourceCode = [currentRequireContext valueForKeyPath:moduleLookupKeyPath];
    if (!moduleSourceCode || ![moduleSourceCode isKindOfClass:[NSString class]])
        return JSValueMakeUndefined(ctx);
    
    // since require isn't implemented in JSC, we will emulate it by wrapping source into anonynous function which returns exports
    // this is a common practice when pre-compiling CommonJS extensions for browsers.
    // obsiously if you have global variable defined in module it's going to leak into global namespace
    // also, requiring module multiple times will re-evaluate code same number of times
    NSString* wrappedSourceCode = [NSString stringWithFormat:@"var module={exports:{}};var exports=module.exports;\n%@;\nreturn exports;",moduleSourceCode];
    
    LogTo(JSVerbose, @"executing require('%@') as\n%@", moduleName, wrappedSourceCode);
    
    JSStringRef jsBody = JSStringCreateWithCFString((__bridge CFStringRef)wrappedSourceCode);
    JSObjectRef fn = JSObjectMakeFunction(ctx, NULL, 0, NULL, jsBody, NULL, 1, exception);
    JSStringRelease(jsBody);
    if (!fn || *exception) {
        WarnJSException(ctx, @"JS function compile failed", *exception);
        return JSValueMakeUndefined(ctx);
    }
    JSValueRef result = JSObjectCallAsFunction(ctx, fn, thisObject, 0, NULL, exception);
    if (*exception) {
        WarnJSException(ctx, @"exception in foojs", *exception);
    }
    
    return result;
}

// This is the body of the JavaScript "log()" function.
static JSValueRef LogCallback(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject,
                              size_t argumentCount, const JSValueRef arguments[],
                              JSValueRef* exception)
{
    NSMutableString *logStr = [NSMutableString string];
    
    for (size_t i = 0; i < argumentCount; i++) {
        JSValueRef argument = arguments[i];
        id arg = JSValueToNSObject/*ValueToID*/(ctx, argument);
        [logStr appendFormat:@"%@", arg];
    }
    LogTo(JS, @"%@", logStr);
    return JSValueMakeUndefined(ctx);
}

// This is the body of the JavaScript "isArray()" function.
static JSValueRef IsArrayCallback(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject,
                              size_t argumentCount, const JSValueRef arguments[],
                              JSValueRef* outException)
{
    if (argumentCount < 1) {
        return JSValueMakeBoolean(ctx, false);
    }
    
    JSObjectRef jsObj = (JSObjectRef)arguments[0];
	JSType type = JSValueGetType(ctx, jsObj);
    if (type != kJSTypeObject) {
        return JSValueMakeBoolean(ctx, false);
    }
    
    JSValueRef exception = NULL;
    
    // Get the Array constructor to check if this Object is an Array
    JSStringRef arrayName = JSStringCreateWithUTF8CString("Array");
    JSObjectRef arrayConstructor = (JSObjectRef)JSObjectGetProperty(ctx, JSContextGetGlobalObject(ctx), arrayName, &exception);
    JSStringRelease(arrayName);
    if (exception) {
        WarnJSException(ctx, @"JS function threw exception", exception);
        if (outException) // bloody pointers
            *outException = exception;
        return JSValueMakeUndefined(ctx);
    }
    
    BOOL isArray = JSValueIsInstanceOfConstructor(ctx, jsObj, arrayConstructor, &exception);
    if (exception) {
        WarnJSException(ctx, @"JS function threw exception", exception);
        if (outException) // bloody pointers
            *outException = exception;
        return JSValueMakeUndefined(ctx);
    }
    
    return JSValueMakeBoolean(ctx, isArray);
}

// This is the body of the JavaScript "toJSON()" function.
static JSValueRef ToJSONCallback(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject,
                                  size_t argumentCount, const JSValueRef arguments[],
                                  JSValueRef* outException)
{
    if (argumentCount < 1) {
        return JSValueMakeBoolean(ctx, false);
    }
    
    JSValueRef exception = NULL;
    JSStringRef str = JSValueCreateJSONString(ctx, arguments[0], 0, &exception);
    if (exception) {
        WarnJSException(ctx, @"JS function threw exception", exception);
        if (outException) // bloody pointers
            *outException = exception;
        return JSValueMakeUndefined(ctx);
    }
    
    JSValueRef jsonStr = JSValueMakeString(ctx, str);
    JSStringRelease(str);
    
    return jsonStr;
}

// This is the body of the JavaScript "sum()" function.
static JSValueRef SumCallback(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject,
                                 size_t argumentCount, const JSValueRef arguments[],
                                 JSValueRef* outException)
{
    double ret = 0;
    for (size_t i = 0; i < argumentCount; i++) {
        JSValueRef value = arguments[i];
        JSType type = JSValueGetType(ctx, value);
        JSValueRef exception = NULL;
        
        if (type == kJSTypeObject) {
            JSObjectRef jsObj = (JSObjectRef)value;
            // Get the Array constructor to check if this Object is an Array
            JSStringRef arrayName = JSStringCreateWithUTF8CString("Array");
            JSObjectRef arrayConstructor = (JSObjectRef)JSObjectGetProperty(ctx, JSContextGetGlobalObject(ctx), arrayName, NULL);
            JSStringRelease(arrayName);

            if( JSValueIsInstanceOfConstructor(ctx, jsObj, arrayConstructor, NULL) ) {
                // Array
                JSStringRef lengthName = JSStringCreateWithUTF8CString("length");
                JSValueRef lengthValue = JSObjectGetProperty(ctx, jsObj, lengthName, &exception);
                if (exception) {
                    WarnJSException(ctx, @"JS function threw exception", exception);
                    if (outException) // bloody pointers
                        *outException = exception;
                    return JSValueMakeUndefined(ctx);
                }

                size_t count = (size_t)JSValueToNumber(ctx, lengthValue, NULL);
                JSStringRelease(lengthName);

                for ( size_t i = 0; i < count; i++ ) {
                    JSValueRef obj = JSObjectGetPropertyAtIndex(ctx, jsObj, (unsigned)i, &exception);
                    if (exception) {
                        WarnJSException(ctx, @"JS function threw exception", exception);
                        if (outException) // bloody pointers
                            *outException = exception;
                        return JSValueMakeUndefined(ctx);
                    }
                    
                    if (JSValueGetType(ctx, obj) == kJSTypeNumber) {
                        double valueDbl = JSValueToNumber(ctx, obj, &exception);
                        if (exception) {
                            WarnJSException(ctx, @"JS function threw exception", exception);
                            if (outException) // bloody pointers
                                *outException = exception;
                            return JSValueMakeUndefined(ctx);
                        }
                        
                        ret += valueDbl;
                    }
                }
            }
        }
        else if (type == kJSTypeNumber || type == kJSTypeString || type == kJSTypeBoolean) {
            double valueDbl = JSValueToNumber(ctx, value, &exception);
            if (exception) {
                WarnJSException(ctx, @"JS function threw exception", exception);
                if (outException) // bloody pointers
                    *outException = exception;
                return JSValueMakeUndefined(ctx);
            }
            
            ret += valueDbl;
        }
    }

    return JSValueMakeNumber(ctx, ret);
}

@implementation CBLJSCompiler
{
    JSGlobalContextRef _context;
}


@synthesize context=_context;


- (instancetype) init {
    self = [super init];
    if (self) {
        _context = JSGlobalContextCreate(NULL);
        if (!_context)
            return nil;
        
        // debugger-freindly
        if (JSGlobalContextSetName) {
            JSStringRef ctxName = JSStringCreateWithCFString((__bridge CFStringRef)NSStringFromClass([self class]));
            JSGlobalContextSetName(_context, ctxName);
            JSStringRelease(ctxName);
        }

        // callback for log
        JSStringRef logName = JSStringCreateWithCFString(CFSTR("log"));
        JSObjectRef logFn = JSObjectMakeFunctionWithCallback(_context, logName, &LogCallback);
        JSObjectSetProperty(_context, JSContextGetGlobalObject(_context),
                            logName, logFn,
                            kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete,
                            NULL);
        JSStringRelease(logName);
        
        // callback for require
        JSStringRef requireName = JSStringCreateWithCFString(CFSTR("require"));
        JSObjectRef requireFn = JSObjectMakeFunctionWithCallback(_context, requireName, &RequireCallback);
        JSObjectSetProperty(_context, JSContextGetGlobalObject(_context),
                            requireName, requireFn,
                            kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete,
                            NULL);
        JSStringRelease(requireName);
        
        // callback for isArray
        JSStringRef isArrayName = JSStringCreateWithCFString(CFSTR("isArray"));
        JSObjectRef isArrayFn = JSObjectMakeFunctionWithCallback(_context, isArrayName, &IsArrayCallback);
        JSObjectSetProperty(_context, JSContextGetGlobalObject(_context),
                            isArrayName, isArrayFn,
                            kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete,
                            NULL);
        JSStringRelease(isArrayName);
        
        // callback for toJSON
        JSStringRef toJSONName = JSStringCreateWithCFString(CFSTR("toJSON"));
        JSObjectRef toJSONFn = JSObjectMakeFunctionWithCallback(_context, toJSONName, &ToJSONCallback);
        JSObjectSetProperty(_context, JSContextGetGlobalObject(_context),
                            toJSONName, toJSONFn,
                            kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete,
                            NULL);
        JSStringRelease(toJSONName);
        
        // callback for sum
        JSStringRef sumName = JSStringCreateWithCFString(CFSTR("sum"));
        JSObjectRef sumFn = JSObjectMakeFunctionWithCallback(_context, sumName, &SumCallback);
        JSObjectSetProperty(_context, JSContextGetGlobalObject(_context),
                            sumName, sumFn,
                            kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete,
                            NULL);
        JSStringRelease(sumName);
    }
    return self;
}


- (void)dealloc {
    if (_context)
        JSGlobalContextRelease(_context);
}


@end



#pragma mark - JS FUNCTION
@implementation CBLJSFunction
{
    CBLJSCompiler* _compiler;
    unsigned _nParams;
    JSObjectRef _fn;
    NSDictionary *_requireContext;
}

@synthesize requireContext=_requireContext;

- (instancetype) initWithCompiler: (CBLJSCompiler*)compiler
                       sourceCode: (NSString*)source
                       paramNames: (NSArray*)paramNames
{
    return [self initWithCompiler: compiler 
                       sourceCode: source 
                       paramNames:paramNames 
                   requireContext:nil];
}

- (instancetype) initWithCompiler: (CBLJSCompiler*)compiler
                       sourceCode: (NSString*)source
                       paramNames: (NSArray*)paramNames
                   requireContext: (NSDictionary*)requireContext
{
    self = [super init];
    if (self) {
        _compiler = compiler;
        _nParams = (unsigned)paramNames.count;
        _requireContext = requireContext;

        // The source code given is a complete function, like "function(doc){....}".
        // But JSObjectMakeFunction wants the source code of the _body_ of a function.
        // Therefore we wrap the given source in an expression that will call it:
        NSString* body = [NSString stringWithFormat: @"return (%@)(%@);",
                                               source, [paramNames componentsJoinedByString: @","]];

        // Compile the function:
        JSStringRef jsParamNames[_nParams];
        for (NSUInteger i = 0; i < _nParams; ++i)
            jsParamNames[i] = JSStringCreateWithCFString((__bridge CFStringRef)paramNames[i]);
        JSStringRef jsBody = JSStringCreateWithCFString((__bridge CFStringRef)body);
        JSValueRef exception;
        _fn = JSObjectMakeFunction(_compiler.context, NULL, _nParams, jsParamNames, jsBody,
                                   NULL, 1, &exception);
        JSStringRelease(jsBody);
        for (NSUInteger i = 0; i < _nParams; ++i)
            JSStringRelease(jsParamNames[i]);
        
        if (!_fn) {
            WarnJSException(_compiler.context, @"JS function compile failed", exception);
            return nil;
        }
        JSValueProtect(_compiler.context, _fn);
    }
    return self;
}

- (JSValueRef) call: (id)param1, ... {
    if (_requireContext) // because nil will cause exception
        NSThread.currentThread.threadDictionary[kCBLJSFunctionCurrentRequireContextKey] = _requireContext;
    JSContextRef context = _compiler.context;
    JSValueRef jsParams[_nParams];
    jsParams[0] = NSObjectToJSValue(context, param1);//IDToValue(context, param1);
    if (_nParams > 1) {
        va_list args;
        va_start(args, param1);
        for (NSUInteger i = 1; i < _nParams; ++i)
            jsParams[i] = NSObjectToJSValue(context, va_arg(args, id));//IDToValue(context, va_arg(args, id));
        va_end(args);
    }
    JSValueRef exception = NULL;
    JSValueRef result = JSObjectCallAsFunction(context, _fn, NULL, _nParams, jsParams, &exception);
    if (!result)
        WarnJSException(context, @"JS function threw exception", exception);
    if (_requireContext)
        [NSThread.currentThread.threadDictionary removeObjectForKey:kCBLJSFunctionCurrentRequireContextKey];
    return result;
}

- (JSValueRef) callWithParams: (NSArray*)params exception: (JSValueRef*)outException {
    if (_requireContext) // because nil will cause exception
        NSThread.currentThread.threadDictionary[kCBLJSFunctionCurrentRequireContextKey] = _requireContext;
    JSContextRef context = _compiler.context;
    NSUInteger params_count = params.count;
    JSValueRef jsParams[params_count];
    for (NSUInteger idx = 0; idx < params_count; idx++) {
        id obj = params[idx];
        jsParams[idx] = NSObjectToJSValue(context, obj);//IDToValue(context, obj);
    }
    JSValueRef exception = NULL;
    JSValueRef result = JSObjectCallAsFunction(context, _fn, NULL, _nParams, jsParams, &exception);
    if (exception) {
        WarnJSException(context, @"JS function threw exception", exception);
        if (outException) // bloody pointers
            *outException = exception;
    }
    if (_requireContext)
        [NSThread.currentThread.threadDictionary removeObjectForKey:kCBLJSFunctionCurrentRequireContextKey];
    return result;
}

- (void)dealloc
{
    if (_fn)
        JSValueUnprotect(_compiler.context, _fn);
}

@end

void WarnJSException(JSContextRef context, NSString* warning, JSValueRef exception) {
    JSStringRef error = JSValueToStringCopy(context, exception, NULL);
    CFStringRef cfError = error ? JSStringCopyCFString(NULL, error) : NULL;
    NSLog(@"*** WARNING: %@: %@", warning, cfError);
    if (cfError)
        CFRelease(cfError);
}


// Converts a JSON-compatible NSObject to a JSValue.
//JSValueRef IDToValue(JSContextRef ctx, id object) {
//    if (object == nil) {
//        return NULL;
//    } else if (object == (id)kCFBooleanFalse || object == (id)kCFBooleanTrue) {
//        return JSValueMakeBoolean(ctx, object == (id)kCFBooleanTrue);
//    } else if (object == [NSNull null]) {
//        return JSValueMakeNull(ctx);
//    } else if ([object isKindOfClass: [NSNumber class]]) {
//        return JSValueMakeNumber(ctx, [object doubleValue]);
//    } else if ([object isKindOfClass: [NSString class]]) {
//        JSStringRef jsStr = JSStringCreateWithCFString((__bridge CFStringRef)object);
//        JSValueRef value = JSValueMakeString(ctx, jsStr);
//        JSStringRelease(jsStr);
//        return value;
//    } else {
//        //FIX: Going through JSON is inefficient.
//        NSData* json = [NSJSONSerialization dataWithJSONObject: object options: 0 error: NULL];
//        if (!json)
//            return NULL;
//        NSString* jsonStr = [[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding];
//        JSStringRef jsStr = JSStringCreateWithCFString((__bridge CFStringRef)jsonStr);
//        JSValueRef value = JSValueMakeFromJSONString(ctx, jsStr);
//        JSStringRelease(jsStr);
//        return value;
//    }
//}

// Converts a JSON-compatible JSValue to an NSObject.
//id ValueToID(JSContextRef ctx, JSValueRef value) {
//    if (!value)
//        return nil;
//    //FIX: Going through JSON is inefficient.
//    //TODO: steal idea from https://github.com/ddb/ParseKit/blob/master/jssrc/PKJSUtils.m
//    JSStringRef jsStr = JSValueCreateJSONString(ctx, value, 0, NULL);
//    if (!jsStr)
//        return nil;
//    NSString* str = (NSString*)CFBridgingRelease(JSStringCopyCFString(NULL, jsStr));
//    JSStringRelease(jsStr);
//    str = [NSString stringWithFormat: @"[%@]", str];    // make it a valid JSON object
//    NSData* data = [str dataUsingEncoding: NSUTF8StringEncoding];
//    NSArray* result = [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL];
//    return [result objectAtIndex: 0];
//}

NSString *JSValueToNSString( JSContextRef ctx, JSValueRef v ) {
    if (ctx == NULL || v == NULL) return nil;
    
	JSStringRef jsString = JSValueToStringCopy( ctx, v, NULL );
	if( !jsString ) return nil;
	
	NSString *string = (__bridge NSString *)JSStringCopyCFString( kCFAllocatorDefault, jsString );
	//[string autorelease];
	JSStringRelease( jsString );
	
	return string;
}

JSValueRef NSStringToJSValue( JSContextRef ctx, NSString *string ) {
	JSStringRef jstr = JSStringCreateWithCFString((__bridge CFStringRef)string);
	JSValueRef ret = JSValueMakeString(ctx, jstr);
	JSStringRelease(jstr);
	return ret;
}

// from https://github.com/phoboslab/Ejecta/blob/master/Source/Ejecta/EJConvert.h

void JSValueUnprotectSafe( JSContextRef ctx, JSValueRef v ) {
	if( ctx && v ) {
		JSValueUnprotect(ctx, v);
	}
}

JSValueRef NSObjectToJSValue( JSContextRef ctx, NSObject *obj ) {
    if (ctx == NULL) { return NULL; }
    
    // method 1
    if (obj == nil) {
        return JSValueMakeNull(ctx);
    } else if (obj == (id)kCFBooleanFalse || obj == (id)kCFBooleanTrue) {
        return JSValueMakeBoolean(ctx, obj == (id)kCFBooleanTrue);
    } else if (obj == [NSNull null]) {
        return JSValueMakeNull(ctx);
    } else if ([obj isKindOfClass: [NSNumber class]]) {
        return JSValueMakeNumber(ctx, [(NSNumber *)obj doubleValue]);
    } else if ([obj isKindOfClass: [NSString class]]) {
        JSStringRef jsStr = JSStringCreateWithCFString((__bridge CFStringRef)(NSString *)obj);
        JSValueRef value = JSValueMakeString(ctx, jsStr);
        JSStringRelease(jsStr);
        return value;
    } else {
        //FIX: Going through JSON is inefficient.
        NSData* json = [NSJSONSerialization dataWithJSONObject: obj options: 0 error: NULL];
        if (!json)
            return NULL;
        NSString* jsonStr = [[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding];
        JSStringRef jsStr = JSStringCreateWithCFString((__bridge CFStringRef)jsonStr);
        JSValueRef value = JSValueMakeFromJSONString(ctx, jsStr);
        JSStringRelease(jsStr);
        return value;
    }

    // method 2
    // TODO: test carefully and only enable then!
    //if (obj == nil) { return JSValueMakeUndefined(ctx); }
    //
    //JSValueRef ret = NULL;
    //
    //// String
    //if( [obj isKindOfClass:NSString.class] ) {
    //    ret = NSStringToJSValue(ctx, (NSString *)obj);
    //}
    //
    //// Number or Bool
    //else if( [obj isKindOfClass:NSNumber.class] ) {
    //    NSNumber *number = (NSNumber *)obj;
    //    if( strcmp(number.objCType, @encode(BOOL)) == 0 ) {
    //        ret = JSValueMakeBoolean(ctx, number.boolValue);
    //    }
    //    else {
    //        ret = JSValueMakeNumber(ctx, number.doubleValue);
    //    }
    //}
    //
    //// Date
    //else if( [obj isKindOfClass:NSDate.class] ) {
    //    NSDate *date = (NSDate *)obj;
    //    JSValueRef timestamp = JSValueMakeNumber(ctx, date.timeIntervalSince1970 * 1000.0);
    //    ret = JSObjectMakeDate(ctx, 1, &timestamp, NULL);
    //}
    //
    //// Array
    //else if( [obj isKindOfClass:NSArray.class] ) {
    //    NSArray *array = (NSArray *)obj;
    //    NSUInteger count = array.count;
    //    JSValueRef *args = malloc(count * sizeof(JSValueRef));
    //    for( NSUInteger i = 0; i < count; i++ ) {
    //        args[i] = NSObjectToJSValue(ctx, array[i] );
    //    }
    //    ret = JSObjectMakeArray(ctx, count, args, NULL);
    //    free(args);
    //}
    //
    //// Dictionary
    //else if( [obj isKindOfClass:NSDictionary.class] ) {
    //    NSDictionary *dict = (NSDictionary *)obj;
    //    ret = JSObjectMake(ctx, NULL, NULL);
    //    for( NSString *key in dict ) {
    //        NSString *value = dict[key];
    //        JSStringRef jsKey = JSStringCreateWithUTF8CString(key.UTF8String);
    //        JSValueRef jsValue = NSObjectToJSValue(ctx, value);
    //        JSObjectSetProperty(ctx, (JSObjectRef)ret, jsKey, jsValue, kJSPropertyAttributeNone, NULL);
    //        JSStringRelease(jsKey);
    //    }
    //}
    //
    //// ObjC null
    //else if ([obj isEqual:[NSNull null]]) {
    //    ret = JSValueMakeNull(ctx);
    //}
    //
    //return ret ? ret : JSValueMakeNull(ctx);
}

NSObject *JSValueToNSObject( JSContextRef ctx, JSValueRef value ) {
    if (ctx == NULL || value == NULL) { return nil; }
    
	JSType type = JSValueGetType(ctx, value);
	
	switch( type ) {
		case kJSTypeString: return JSValueToNSString(ctx, value);
		case kJSTypeBoolean: return [NSNumber numberWithBool:JSValueToBoolean(ctx, value)];
		case kJSTypeNumber: return [NSNumber numberWithDouble:JSValueToNumber(ctx, value, NULL)];
		case kJSTypeNull: return [NSNull null];
		case kJSTypeUndefined: return nil;
		case kJSTypeObject: break;
	}
	
	if( type == kJSTypeObject ) {
		JSObjectRef jsObj = (JSObjectRef)value;
		
		// Get the Array constructor to check if this Object is an Array
		JSStringRef arrayName = JSStringCreateWithUTF8CString("Array");
		JSObjectRef arrayConstructor = (JSObjectRef)JSObjectGetProperty(ctx, JSContextGetGlobalObject(ctx), arrayName, NULL);
		JSStringRelease(arrayName);
        
		if( JSValueIsInstanceOfConstructor(ctx, jsObj, arrayConstructor, NULL) ) {
			// Array
			JSStringRef lengthName = JSStringCreateWithUTF8CString("length");
            JSValueRef lengthValue = JSObjectGetProperty(ctx, jsObj, lengthName, NULL);
			int count = (int)JSValueToNumber(ctx, lengthValue, NULL);
			JSStringRelease(lengthName);
			
			NSMutableArray *array = [NSMutableArray arrayWithCapacity:count];
			for( int i = 0; i < count; i++ ) {
				NSObject *obj = JSValueToNSObject(ctx, JSObjectGetPropertyAtIndex(ctx, jsObj, i, NULL));
				[array addObject:(obj ? obj : NSNull.null)];
			}
			return array;
		}
		else {
			// Plain Object
			JSPropertyNameArrayRef properties = JSObjectCopyPropertyNames(ctx, jsObj);
			size_t count = JSPropertyNameArrayGetCount(properties);
			
			NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:count];
			for( size_t i = 0; i < count; i++ ) {
				JSStringRef propName = JSPropertyNameArrayGetNameAtIndex(properties, i);
                NSString *name = (__bridge NSString *)JSStringCopyCFString( kCFAllocatorDefault, propName );
                
                JSValueRef exception = NULL;
                JSValueRef propValue = JSObjectGetProperty(ctx, jsObj, propName, &exception);
                
				NSObject *obj = JSValueToNSObject(ctx, propValue);
				if (!obj) continue;
                
				dict[name] = obj;//obj ? obj : NSNull.null;
				//[name release];
			}
			
			JSPropertyNameArrayRelease(properties);
			return dict;
		}
	}
	
	return nil;
}
// * * *
