//
//  CBLMisc.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/13/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLMisc.h"

#import "CollectionUtils.h"


#ifdef GNUSTEP
#import <openssl/sha.h>
#import <uuid/uuid.h>   // requires installing "uuid-dev" package on Ubuntu
#else
#define COMMON_DIGEST_FOR_OPENSSL
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#endif


#ifdef GNUSTEP
static double CouchbaseLiteVersionNumber = 0.7;
#else
extern double CouchbaseLiteVersionNumber; // Defined in Xcode-generated CouchbaseLite_vers.c
#endif


NSArray<NSString *> * getPinnedCerificates(void);
NSArray<NSString *> * getPinnedPublicKeys(void);

NSString* CBLVersionString( void ) {
return $sprintf(@"%g", CouchbaseLiteVersionNumber);
}


NSString* CBLCreateUUID() {
#ifdef GNUSTEP
    uuid_t uuid;
    uuid_generate(uuid);
    char cstr[37];
    uuid_unparse_lower(uuid, cstr);
    return [[[NSString alloc] initWithCString: cstr encoding: NSASCIIStringEncoding] autorelease];
#else
    
    CFUUIDRef uuid = CFUUIDCreate(NULL);
#ifdef __OBJC_GC__
    CFStringRef uuidStrRef = CFUUIDCreateString(NULL, uuid);
    NSString *uuidStr = (NSString *)uuidStrRef;
    CFRelease(uuidStrRef);
#else
    NSString *uuidStr = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
#endif
    CFRelease(uuid);
    return uuidStr;
#endif
}


NSData* CBLSHA1Digest( NSData* input ) {
    unsigned char digest[SHA_DIGEST_LENGTH];
    SHA_CTX ctx;
    SHA1_Init(&ctx);
    SHA1_Update(&ctx, input.bytes, input.length);
    SHA1_Final(digest, &ctx);
    return [NSData dataWithBytes: &digest length: sizeof(digest)];
}

NSData* CBLSHA256Digest( NSData* input ) {
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256_CTX ctx;
    SHA256_Init(&ctx);
    SHA256_Update(&ctx, input.bytes, input.length);
    SHA256_Final(digest, &ctx);
    return [NSData dataWithBytes: &digest length: sizeof(digest)];
}


NSString* CBLHexSHA1Digest( NSData* input ) {
    unsigned char digest[SHA_DIGEST_LENGTH];
    SHA_CTX ctx;
    SHA1_Init(&ctx);
    SHA1_Update(&ctx, input.bytes, input.length);
    SHA1_Final(digest, &ctx);
    return CBLHexFromBytes(&digest, sizeof(digest));
}

NSString* CBLHexFromBytes( const void* bytes, size_t length) {
    char hex[2*length + 1];
    char *dst = &hex[0];
    for( size_t i=0; i<length; i+=1 )
        dst += sprintf(dst,"%02x", ((const uint8_t*)bytes)[i]); // important: generates lowercase!
    return [[NSString alloc] initWithBytes: hex
                                     length: 2*length
                                   encoding: NSASCIIStringEncoding];
}


NSData* CBLHMACSHA1(NSData* key, NSData* data) {
    UInt8 hmac[SHA_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA1, key.bytes, key.length, data.bytes, data.length, &hmac);
    return [NSData dataWithBytes: hmac length: sizeof(hmac)];
}

NSData* CBLHMACSHA256(NSData* key, NSData* data) {
    UInt8 hmac[SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, &hmac);
    return [NSData dataWithBytes: hmac length: sizeof(hmac)];
}


NSComparisonResult CBLSequenceCompare( SequenceNumber a, SequenceNumber b) {
    SInt64 diff = a - b;
    return diff > 0 ? 1 : (diff < 0 ? -1 : 0);
}


NSString* CBLEscapeID( NSString* docOrRevID ) {
#ifdef GNUSTEP
    docOrRevID = [docOrRevID stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
    docOrRevID = [docOrRevID stringByReplacingOccurrencesOfString: @"&" withString: @"%26"];
    docOrRevID = [docOrRevID stringByReplacingOccurrencesOfString: @"/" withString: @"%2F"];
    return docOrRevID;
#else
    NSString* unescapedPrefix = nil;
    NSString* substrToEscape = nil;
    
    if ([docOrRevID hasPrefix:@"_design/"] || [docOrRevID hasPrefix:@"_local/"]) {
        NSRange firstBackslash = [docOrRevID rangeOfString:@"/"];
        if (firstBackslash.location != NSNotFound) { // just in case
            substrToEscape = [docOrRevID substringFromIndex: firstBackslash.location + 1];
            unescapedPrefix = [docOrRevID substringToIndex: firstBackslash.location + 1];
        }
    } else {
        substrToEscape = docOrRevID;
    }
    
    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                  (CFStringRef)substrToEscape,
                                                                  NULL, (CFStringRef)@"?&/",
                                                                  kCFStringEncodingUTF8);
    
    if (unescapedPrefix) {
        NSString *result = [unescapedPrefix stringByAppendingString:(__bridge_transfer NSString *)escaped];
        
        #ifdef __OBJC_GC__
        NSMakeCollectable(escaped);
        #else
        //CFRelease(escaped); // FIXME: figure out why it crashes the app if uncommented
        #endif
        
        return result;
    } else {
        #ifdef __OBJC_GC__
        return NSMakeCollectable(escaped);
        #else
        return (__bridge_transfer NSString *)escaped;
        #endif
    }
#endif
}


NSString* CBLEscapeURLParam( NSString* param ) {
#ifdef GNUSTEP
    param = [param stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
    param = [param stringByReplacingOccurrencesOfString: @"&" withString: @"%26"];
    param = [param stringByReplacingOccurrencesOfString: @"+" withString: @"%2B"];
    return param;
#else
    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                  (CFStringRef)param,
                                                                  NULL, (CFStringRef)@"&+",
                                                                  kCFStringEncodingUTF8);
    #ifdef __OBJC_GC__
    return NSMakeCollectable(escaped);
    #else
    return (__bridge_transfer NSString *)escaped;
    #endif
#endif
}


NSString* CBLQuoteString( NSString* param ) {
    NSMutableString* quoted = [param mutableCopy];
    [quoted replaceOccurrencesOfString: @"\\" withString: @"\\\\"
                               options: NSLiteralSearch
                                 range: NSMakeRange(0, quoted.length)];
    [quoted replaceOccurrencesOfString: @"\"" withString: @"\\\""
                               options: NSLiteralSearch
                                 range: NSMakeRange(0, quoted.length)];
    [quoted insertString: @"\"" atIndex: 0];
    [quoted appendString: @"\""];
    return quoted;
}


NSString* CBLUnquoteString( NSString* param ) {
    if (![param hasPrefix: @"\""])
        return param;
    if (![param hasSuffix: @"\""] || param.length < 2)
        return nil;
    param = [param substringWithRange: NSMakeRange(1, param.length - 2)];
    if ([param rangeOfString: @"\\"].length == 0)
        return param;
    NSMutableString* unquoted = [param mutableCopy];
    for (NSUInteger pos = 0; pos < unquoted.length; ) {
        NSRange r = [unquoted rangeOfString: @"\\"
                                    options: NSLiteralSearch
                                      range: NSMakeRange(pos, unquoted.length-pos)];
        if (r.length == 0)
            break;
        [unquoted deleteCharactersInRange: r];
        pos = r.location + 1;
        if (pos > unquoted.length)
            return nil;
    }
    return unquoted;
}


NSString* CBLAbbreviate( NSString* str ) {
    if (str.length <= 10)
        return str;
    NSMutableString* abbrev = [str mutableCopy];
    [abbrev replaceCharactersInRange: NSMakeRange(4, abbrev.length - 8) withString: @".."];
    return abbrev;
}


BOOL CBLIsOfflineError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    if ($equal(domain, NSURLErrorDomain))
        return code == NSURLErrorDNSLookupFailed
            || code == NSURLErrorNotConnectedToInternet
#ifndef GNUSTEP
            || code == NSURLErrorInternationalRoamingOff
#endif
        ;
    return NO;
}


BOOL CBLIsFileExistsError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    return ($equal(domain, NSPOSIXErrorDomain) && code == EEXIST)
#ifndef GNUSTEP
        || ($equal(domain, NSCocoaErrorDomain) && code == NSFileWriteFileExistsError)
#endif
        ;
}

static BOOL CBLIsFileNotFoundError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    return ($equal(domain, NSPOSIXErrorDomain) && code == ENOENT)
#ifndef GNUSTEP
        || ($equal(domain, NSCocoaErrorDomain) && code == NSFileNoSuchFileError)
#endif
    ;
}


BOOL CBLMayBeTransientError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    if ($equal(domain, NSURLErrorDomain)) {
        return code == NSURLErrorTimedOut || code == NSURLErrorCannotConnectToHost
                                          || code == NSURLErrorNetworkConnectionLost;
    } else if ($equal(domain, CBLHTTPErrorDomain)) {
        // Internal Server Error, Bad Gateway, Service Unavailable or Gateway Timeout:
        return code == 500 || code == 502 || code == 503 || code == 504;
    } else {
        return NO;
    }
}


BOOL CBLIsPermanentError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    if ($equal(domain, NSURLErrorDomain)) {
        return code == NSURLErrorBadURL || code == NSURLErrorUnsupportedURL;
    } else if ($equal(domain, CBLHTTPErrorDomain)) {
        return code >= 400 && code <= 499;
    } else {
        return NO;
    }
}


BOOL CBLRemoveFileIfExists(NSString* path, NSError** outError) {
    NSError* error;
    if ([[NSFileManager defaultManager] removeItemAtPath: path error: &error]) {
        LogTo(CBLDatabase, @"Deleted file %@", path);
        return YES;
    } else if (CBLIsFileNotFoundError(error)) {
        return YES;
    } else {
        if (outError)
            *outError = error;
        return NO;
    }
}


NSURL* CBLURLWithoutQuery( NSURL* url ) {
#ifdef GNUSTEP
    // No CFURL on GNUstep :(
    NSString* str = url.absoluteString;
    NSRange q = [str rangeOfString: @"?"];
    if (q.length == 0)
        return url;
    return [NSURL URLWithString: [str substringToIndex: q.location]];
#else
    // Strip anything after the URL's path (i.e. the query string)
    CFURLRef cfURL = (__bridge CFURLRef)url;
    CFRange range = CFURLGetByteRangeForComponent(cfURL, kCFURLComponentResourceSpecifier, NULL);
    if (range.length == 0) {
        return url;
    } else {
        CFIndex size = CFURLGetBytes(cfURL, NULL, 0);
        if (size > 8000)
            return url;  // give up
        UInt8 bytes[size];
        CFURLGetBytes(cfURL, bytes, size);
        NSURL *url = (__bridge_transfer NSURL *)CFURLCreateWithBytes(NULL, bytes, range.location - 1, kCFStringEncodingUTF8, NULL);
    #ifdef __OBJC_GC__
        return NSMakeCollectable(url);
    #else
        return url;
    #endif
    }
#endif
}


NSURL* CBLAppendToURL(NSURL* baseURL, NSString* toAppend) {
    if (toAppend.length == 0 || $equal(toAppend, @"."))
        return baseURL;
    NSMutableString* urlStr = baseURL.absoluteString.mutableCopy;
    if (![urlStr hasSuffix: @"/"])
        [urlStr appendString: @"/"];
    [urlStr appendString: toAppend];
    return [NSURL URLWithString: urlStr];
}

NSData* CBLDataEncode(NSData *data, NSString *key) {
    if (!key) return data;
    
    // 'key' should be 32 bytes for AES256, will be null-padded otherwise
    char keyPtr[kCCKeySizeAES256+1]; // room for terminator (unused)
    bzero(keyPtr, sizeof(keyPtr)); // fill with zeroes (for padding)
    
    BOOL patchNeeded = key.length > kCCKeySizeAES256;
    if (patchNeeded) {
        key = [key substringToIndex:kCCKeySizeAES256]; // Ensure that the key isn't longer than what's needed (kCCKeySizeAES256)
    }
    
    // fetch key data
    [key getCString:keyPtr maxLength:sizeof(keyPtr) encoding:NSUTF8StringEncoding];
    
    if (patchNeeded) {
        keyPtr[0] = '\0';  // Previous iOS version than iOS7 set the first char to '\0' if the key was longer than kCCKeySizeAES256
    }
    
    NSUInteger dataLength = [data length];
    
    //See the doc: For block ciphers, the output size will always be less than or
    //equal to the input size plus the size of one block.
    //That's why we need to add the size of one block here
    size_t bufferSize = dataLength + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);
    
    size_t numBytesEncrypted = 0;
    CCCryptorStatus cryptStatus = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                          keyPtr, kCCKeySizeAES256,
                                          NULL /* initialization vector (optional) */,
                                          data.bytes, dataLength, /* input */
                                          buffer, bufferSize, /* output */
                                          &numBytesEncrypted);
    if (cryptStatus == kCCSuccess) {
        //the returned NSData takes ownership of the buffer and will free it on deallocation
        return [NSData dataWithBytesNoCopy:buffer length:numBytesEncrypted];
    }
    
    free(buffer); //free the buffer;
    return nil;
}

NSData* CBLDataDecode(NSData *data, NSString *key) {
    if (!key) return data;    
    
    // 'key' should be 32 bytes for AES256, will be null-padded otherwise
    char keyPtr[kCCKeySizeAES256+1]; // room for terminator (unused)
    bzero(keyPtr, sizeof(keyPtr)); // fill with zeroes (for padding)
    
    BOOL patchNeeded = key.length > kCCKeySizeAES256;
    if (patchNeeded) {
        key = [key substringToIndex:kCCKeySizeAES256]; // Ensure that the key isn't longer than what's needed (kCCKeySizeAES256)
    }
    
    // fetch key data
    [key getCString:keyPtr maxLength:sizeof(keyPtr) encoding:NSUTF8StringEncoding];
    
    if (patchNeeded) {
        keyPtr[0] = '\0';  // Previous iOS version than iOS7 set the first char to '\0' if the key was longer than kCCKeySizeAES256
    }
    
    NSUInteger dataLength = [data length];
    
    //See the doc: For block ciphers, the output size will always be less than or
    //equal to the input size plus the size of one block.
    //That's why we need to add the size of one block here
    size_t bufferSize = dataLength + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);
    
    size_t numBytesDecrypted = 0;
    CCCryptorStatus cryptStatus = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                          keyPtr, kCCKeySizeAES256,
                                          NULL /* initialization vector (optional) */,
                                          data.bytes, dataLength, /* input */
                                          buffer, bufferSize, /* output */
                                          &numBytesDecrypted);
    if (cryptStatus == kCCSuccess) {
        //the returned NSData takes ownership of the buffer and will free it on deallocation
        return [NSData dataWithBytesNoCopy:buffer length:numBytesDecrypted];
    }
    
    free(buffer); //free the buffer;
    return nil;
}


NSArray<NSString *> * getPinnedCerificates(void) {
    // List is obtained via this script:
    // https://github.com/Spotme/tool-emergency-hacks/blob/master/dump-cloud-certificate-hashes/hash_cloud_certs.py
    return @[
             @"8MlkzZFgriMj+xxs53Nmof2LKlk2fpwXKabp1fmCVQrOjQC9AwdwnRWHpv5AFE71vrkEqEXQhzdw4DSvIRY8oQ==",
             @"4Fn7pesgxtmCojAhSoh6FCBbpx9RCZ92zVfz1vAZjIJPzyRess5ZTxGI5lJa4C9QTo6rM0SLbWSgvZTqCrQVpQ==",
             @"QlXn6WZ1vfBcUqJ7KaffpITZNYH1ZoMns1LV8x+nHS7dkgSXbE+SPEmyJwwEzGmjODSgJ9Gzola5m+3UBAu/3w==",
             @"RoJLyOqrW3i8yxfGOIq6RJGzIZif4nyF1deD4gvNGQ4wlHoalNkycm/k65K6lmVoDBLnMV9htSyd8kSyyTC94w==",
             @"mFH6ulQmAbFT8q1c5WY66d4m0y4o9V2mTvwu8NxLvA76149Q7UUL698zJHTU9ZdbngGkiFw2sS/eG+BWEqLs8A==",
             @"LiqgRa4ZgrWkeXv/yJGc6EMHTToZv6U/LwCbfLtq79RQIridWaoe4JeV+qDpZ2N3P8HijtCkFgqsk7YdewMxlA==",
             @"6oAiHM06cna7OSRm4sDKZp7pnc4TA5crfKUk7W10/oQHq85wceruOW0SxxWTMUNwu4qyBqd4hDRkAIDPiYRnCQ==",
             @"mFH6ulQmAbFT8q1c5WY66d4m0y4o9V2mTvwu8NxLvA76149Q7UUL698zJHTU9ZdbngGkiFw2sS/eG+BWEqLs8A==",
             @"3rT3nGGckCDQyqzM4r4mGyl+pDhHfrdJHX8iX4oa9TxcpIK2DFqoZ0Y61Isfsx5dAcZUnXtNhjsDaWY1yhzdDw==",
             @"vvGOqSEXbQVpNjIlXzI2Jip9gqJiD0bWxqi7/qhq4WmL4cbmLiBxt93NKeiYbZsrQVoL0+986Il6ys1JVEKuUA==",
             @"C8hkcL9uRd9m/KrDIk2mS2vbBc7knN37GzEdsiNzs/KaR4TynjLsydGIuaDaMvXXxi6eIf4cOzb1yC8VNWCBHg==",
             @"wMdDc05AMlAfYCdHKWzz7MC//A0xGQXNGmvjXHx52yBF7Ab4/LxblXFwhw9iBntfTii3tpZO8tVLdVOF8cAqSQ==",
             @"LO7UGF5ie0LHZ4vo9CSnVS7+hEdXAngJRVXbppbBeRaJqBtxH2B+ZkibZ2fBK63s3zGXNsNskGJmPHWW7LQgPA==",
             @"6OzNscn6tlAb1hEJM92aq7ooRQjR+cf7B/aO+dSZWo/n4IC1WDFMIcGglEOzfB/yoTheVVBIL92jH0SfVbYWcw==",
             @"xq/ydoHlNWqLl96jCJfTLckiq0SamyJXmsKYBOxdnmTnlQdAhBK3R7gIbAJwwpeRnzz/lq6jBRZIPvq1NeIJdQ==",
             @"ubjCFx89HycEvTqOx6nU3QXkwno+axeKkmVJ42zna2kKOAWQNCyx9ezpEMn3WwWK+YGOTGAgcqgMzg9cD9f+nw==",
             @"O0w/8r6mN5Sa25WzMYQI+eeHn7xlO/hmTPZrf/0hGj4THdmR2JoimimRstRh2g8QvnL8e2MPLGypNFbNYNM5cw==",
             @"lI3FkIRPpqKtHqefS1oDDr0jp0H4qeFhe/mRyi2iw/aIj1vRzup8JWkrmw7uy/k+W3Mk8nYnDH/s9TcjnWtEzQ==",
             @"CwrfD2tY4CBU/ADdYYta5b00BRCUk6DheKWwBebQF4uMRJOptDiadC1RJWIDclqy5VaPkkcR5Q5AP0bf83BuZQ==",
             @"K8Ay6BBbpwqLTcPNuMlWK8soinNQoBMhvb13P5sEbMUOZc6hGVjRHllh566LRd18C13ScNe9oeco/vHygKuj6g==",
             @"pYrjbicx+xrURJDRiqGuxEwNYcJCo06u4skk9jhw7sKBygEAGvdowkXKcE76YEsP87FHEnpqXbBOC+MHH5Mr/w==",
             @"KmpegCAamjUxykoLvoy6N5JDqfI4BCvpwOxyw3nk4a/3wpmiSgb9AikwnGFiJP5Kz6L7HuQ/y/QC/zl6wnvZJw=="
             ];
}


NSArray<NSString *> * getPinnedPublicKeys(void) {
    // Pin only staging7/8 wildcard certificates pkey for now
    return @[@"owjUQOf/ZY894ZLo3ivSixlNexZi6PcCYm2Z5+S57xYuF0M6OdtM2obTbtmCE1Vj6WhRGBX75TSqakYLt/ov9Q=="];
}


BOOL verifyCertIsInPinnedSetForServerTrust(SecTrustRef trust) {
    BOOL success = NO;
    if (trust && SecTrustGetCertificateCount(trust) > 0) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(trust, 0);
        if (certificate) {
            NSData *certData = CFBridgingRelease(SecCertificateCopyData(certificate));
            if (certData && certData.length) {
                NSMutableData *keyWithHeaderRawData = [NSMutableData new];
                [keyWithHeaderRawData appendData:certData];
                uint8_t hash[CC_SHA512_DIGEST_LENGTH] = {0};
                if (CC_SHA512([keyWithHeaderRawData bytes], (CC_LONG)[keyWithHeaderRawData length], hash)) {
                    NSData *sha = [NSData dataWithBytes:hash length:CC_SHA512_DIGEST_LENGTH];
                    NSString *base64Data = [sha base64EncodedStringWithOptions:0];
                    if (base64Data && base64Data.length) {
                        success = [getPinnedCerificates() containsObject:base64Data];
                    }
                }
            }
        }
    }
    return success;
}


BOOL verifyPKeyIsInPinnedSetForServerTrust(SecTrustRef trust) {
    
    BOOL success = NO;
    const int kHeaderLength = 24;
    const uint8_t rsa2048Header[kHeaderLength] = {0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48,
        0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00};
    
    if (trust && SecTrustGetCertificateCount(trust) > 0) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(trust, 0);
        if (certificate) {
            SecKeyRef serverPublicKey = SecCertificateCopyPublicKey(certificate);
            if (serverPublicKey) {
                CFErrorRef keyError = NULL;
                NSData *serverPublicKeyData = CFBridgingRelease(SecKeyCopyExternalRepresentation(serverPublicKey, &keyError));
                if (serverPublicKeyData && !keyError && serverPublicKeyData.length) {
                    NSMutableData *keyWithHeaderRawData = [[NSMutableData alloc] initWithBytes:rsa2048Header
                                                                                        length:kHeaderLength];
                    [keyWithHeaderRawData appendData:serverPublicKeyData];
                    uint8_t hash[CC_SHA512_DIGEST_LENGTH] = {0};
                    if (CC_SHA512([keyWithHeaderRawData bytes], (CC_LONG)[keyWithHeaderRawData length], hash)) {
                        NSData *sha = [NSData dataWithBytes:hash length:CC_SHA512_DIGEST_LENGTH];
                        NSString *base64Data = [sha base64EncodedStringWithOptions:0];
                        if (base64Data) {
                            success = [getPinnedPublicKeys() containsObject:base64Data];
                        }
                    }
                }
            }
        }
    }
    return success;
}


NSArray* CBLSplitURLPath(NSURL *URL) {
    // Unfortunately can't just call url.path because that converts %2F to a '/'.
#ifdef GNUSTEP
    NSString* pathString = [url pathWithEscapes];
#else
#ifdef __OBJC_GC__
    NSString* pathString = NSMakeCollectable(CFURLCopyPath((CFURLRef)url));
#else
    NSString* pathString = (__bridge_transfer NSString *)CFURLCopyPath((__bridge CFURLRef)URL);
#endif
#endif
    NSMutableArray* path = $marray();
    for (NSString* comp in [pathString componentsSeparatedByString: @"/"]) {
        if ([comp length] > 0) {
            NSString* unescaped = [comp stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            if (!unescaped) {
                path = nil;     // bad URL
                break;
            }
            [path addObject: unescaped];
        }
    }
#ifndef GNUSTEP
#endif
    return path;
}

TestCase(CBLQuoteString) {
    CAssertEqual(CBLQuoteString(@""), @"\"\"");
    CAssertEqual(CBLQuoteString(@"foo"), @"\"foo\"");
    CAssertEqual(CBLQuoteString(@"f\"o\"o"), @"\"f\\\"o\\\"o\"");
    CAssertEqual(CBLQuoteString(@"\\foo"), @"\"\\\\foo\"");
    CAssertEqual(CBLQuoteString(@"\""), @"\"\\\"\"");
    CAssertEqual(CBLQuoteString(@""), @"\"\"");

    CAssertEqual(CBLUnquoteString(@""), @"");
    CAssertEqual(CBLUnquoteString(@"\""), nil);
    CAssertEqual(CBLUnquoteString(@"\"\""), @"");
    CAssertEqual(CBLUnquoteString(@"\"foo"), nil);
    CAssertEqual(CBLUnquoteString(@"foo\""), @"foo\"");
    CAssertEqual(CBLUnquoteString(@"foo"), @"foo");
    CAssertEqual(CBLUnquoteString(@"\"foo\""), @"foo");
    CAssertEqual(CBLUnquoteString(@"\"f\\\"o\\\"o\""), @"f\"o\"o");
    CAssertEqual(CBLUnquoteString(@"\"\\foo\""), @"foo");
    CAssertEqual(CBLUnquoteString(@"\"\\\\foo\""), @"\\foo");
    CAssertEqual(CBLUnquoteString(@"\"foo\\\""), nil);
}

TestCase(TDEscapeID) {
    CAssertEqual(CBLEscapeID(@"foobar"), @"foobar");
    CAssertEqual(CBLEscapeID(@"<script>alert('ARE YOU MY DADDY?')</script>"),
                            @"%3Cscript%3Ealert('ARE%20YOU%20MY%20DADDY%3F')%3C%2Fscript%3E");
    CAssertEqual(CBLEscapeID(@"foo/bar"), @"foo%2Fbar");
    CAssertEqual(CBLEscapeID(@"foo&bar"), @"foo%26bar");
}
