//
//  CBLShowFunction+Internal.m
//  CouchbaseLite
//
//  Created by Igor Evsukov on 7/27/13.
//
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//


#import "CBLShowFunction+Internal.h"
#import "CBLManager+Internal.h"
#import "CBL_Shared.h"
#import "CBLJSShowFunctionCompiler.h"

@implementation CBLShowFunction (Internal)

- (BOOL) compileFromDesignDoc: (NSDictionary*)designDoc
                     showName: (NSString*)showName {
    
    NSString* className = NSStringFromClass([CBLJSShowFunctionCompiler class]);
    CBLJSShowFunctionCompiler* showFuncCompiler = [self.database.manager.shared valueForType: className
                                                                                        name: className
                                                                             inDatabaseNamed: self.database.name];
    if (!showFuncCompiler) {
        JSGlobalContextRef globalCtxRef = self.database.JSContext.JSGlobalContextRef;
        showFuncCompiler = [[CBLJSShowFunctionCompiler alloc] initWithJSGlobalContextRef: globalCtxRef];
        
        [self.database.manager.shared setValue: showFuncCompiler
                                       forType: className
                                          name: className
                               inDatabaseNamed: self.database.name];
    }
    
    NSDictionary* shows = designDoc[@"shows"];
    if (!shows || ![shows isKindOfClass: [NSDictionary class]]) {
        LogTo(View, @"ddoc %@ - missing show functions",
              $sprintf(@"%@-%@", designDoc[@"_id"], designDoc[@"_rev"]));
        return NO;
    }
    
    NSString* showSource = shows[showName];
    if (!showSource || ![showSource isKindOfClass: [NSString class]]) {
        LogTo(View, @"ddoc %@ - missing show function: %@",
              $sprintf(@"%@-%@", designDoc[@"_id"], designDoc[@"_rev"]), showName);
        return NO;
    }
    
    CBLShowFunctionBlock showFunctionBlock = [showFuncCompiler compileShowFunction: $sprintf(@"%@/_show/%@-%@", designDoc[@"_id"], showName, designDoc[@"_rev"])
                                                                            source: showSource
                                                                          userInfo: designDoc];
    
    if (!showFunctionBlock) {
        Warn(@"Show function %@ has unknown source function: %@", _name, showSource);
        return NO;
    }
    
    self.showFunctionBlock = showFunctionBlock;
    return YES;
}


@end
