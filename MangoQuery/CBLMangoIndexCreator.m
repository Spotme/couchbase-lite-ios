//
//  CBLMangoIndexCreator.m
//  CouchbaseLite
//
//  Created by Alexander  Karaberov on 22.02.19.
//

#import "CBLMangoIndexCreator.h"
#import "CBLMangoIndex.h"
#import "CBLDatabase.h"
#import "FMDatabase.h"
#import "CBLDatabase+Internal.h"


@implementation CBLMangoIndexCreator

+ (nullable NSString *)ensureIndexed:(CBLMangoIndex *)index
                          inDatabase:(CBL_FMDatabase *)database {
    return @"";
}

@end
