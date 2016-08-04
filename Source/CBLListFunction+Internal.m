//
//  CBLListFunction+Internal.m
//  CouchbaseLite
//
//  Created by Igor Evsukov on 7/28/13.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//

#import "CBLListFunction+Internal.h"
#import "CBL_Shared.h"
#import "CBLJSListFunctionCompiler.h"

@implementation CBLListFunction (Internal)

- (BOOL) compileFromDesignDoc: (NSDictionary*)designDoc
                     listName: (NSString*)listName {
    
    NSString* className = NSStringFromClass([CBLJSListFunctionCompiler class]);
    CBLJSListFunctionCompiler* listFuncCompiler = [self.database.shared valueForType: className
                                                                                name: className
                                                                     inDatabaseNamed: self.database.name];
    if (!listFuncCompiler) {
        JSGlobalContextRef globalCtxRef = self.database.JSContext.JSGlobalContextRef;
        listFuncCompiler = [[CBLJSListFunctionCompiler alloc] initWithJSGlobalContextRef: globalCtxRef];
        
        [self.database.shared setValue: listFuncCompiler
                               forType: className
                                  name: className
                       inDatabaseNamed: self.database.name];
    }
    
    NSDictionary* lists = designDoc[@"lists"];
    if (!lists || ![lists isKindOfClass: [NSDictionary class]]) {
        LogTo(View, @"ddoc %@ - missing list functions",
              $sprintf(@"%@-%@", designDoc[@"_id"], designDoc[@"_rev"]));
        return NO;
    }
    
    NSString* listSource = lists[listName];
    if (!listSource || ![listSource isKindOfClass: [NSString class]]) {
        LogTo(View, @"ddoc %@ - missing list function: %@",
              $sprintf(@"%@-%@", designDoc[@"_id"], designDoc[@"_rev"]), listName);
        return NO;
    }
    
    CBLListFunctionBlock listFunctionBlock = [listFuncCompiler compileListFunction: $sprintf(@"%@/_list/%@-%@", designDoc[@"_id"], listName, designDoc[@"_rev"])
                                                                            source: listSource
                                                                          userInfo: designDoc];
    
    if (!listFunctionBlock) {
        Warn(@"Show function %@ has unknown source function: %@", _name, listSource);
        return NO;
    }
    
    self.listFunctionBlock = listFunctionBlock;
    return YES;
}

@end
