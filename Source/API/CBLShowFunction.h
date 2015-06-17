//
//  CBLShowFunction.h
//  CouchbaseLite
//
//  Created by Igor Evsukov on 7/27/13.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//

#import <Foundation/Foundation.h>
@class CBLDatabase, CBLRevision, CBLFunctionResult;

typedef CBLFunctionResult* (^CBLShowFunctionBlock)(NSDictionary *revision, NSDictionary *params);

#define SHOWBLOCK(BLOCK) ^CBLFunctionResult(NSDictionary *revision, NSDictionary *params){BLOCK}

/**  An external object that knows how to map source code of some sort into executable functions. Similar to the CBLViewCompiler */
@protocol CBLShowFunctionCompiler <NSObject>
@required
- (CBLShowFunctionBlock) compileShowFunction: (NSString*)showSource language: (NSString*)language userInfo: (NSDictionary*)userInfo;
@end


/** A "show function" in a CouchbaseLite database -- essentially a stored function used to modify doc format.
    Show functions doesn't make much sense in native code, but very useful when declared in design document. */
@interface CBLShowFunction : NSObject
{
    @private
    CBLDatabase* __weak _db;
    NSString *_name;
}

/** The database that owns this show function. */
@property (readonly) CBLDatabase* database;

/** The name of the show function.
    In case of JS function it will be ddoc/showfuncname */
@property (readonly) NSString* name;

/** The map function that controls how index rows are created from documents. */
@property (readwrite) CBLShowFunctionBlock showFunctionBlock;

/** Invokes showFunctionBlock with revision properties, params will be passed as a second parameter */
- (CBLFunctionResult*)runWithRevision: (CBLRevision *)revision params: (NSDictionary *)params;

- (CBLFunctionResult*)runWithRevisionProperties: (NSDictionary *)revisionProperties params: (NSDictionary *)params;


@end
