//
//  CBLMangoIndexCreator.h
//  CouchbaseLite
//
//  Created by Alexander  Karaberov on 22.02.19.
//

#import <Foundation/Foundation.h>

@class CBLDatabase;
@class CBLMangoIndex;
@class CBL_FMDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface CBLMangoIndexCreator : NSObject

/**
 Add a single, possibly compound, index for the given field names.
 @returns name of created index
 */
+ (nullable NSString *)ensureIndexed:(CBLMangoIndex *)index
                          inDatabase:(CBL_FMDatabase *)database;


@end

NS_ASSUME_NONNULL_END
