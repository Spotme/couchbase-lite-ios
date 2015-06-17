//
//  CBLJSViewCompiler.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/4/13.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//

#import "CBLJSFunction.h"
#import "CBLView.h"

@interface CBLJSViewCompiler : CBLJSCompiler

- (CBLMapBlock) compileMapFunction: (NSString*)mapSource userInfo: (NSDictionary*)userInfo;

- (CBLReduceBlock) compileReduceFunction: (NSString*)reduceSource userInfo: (NSDictionary*)userInfo;

@end


