//
//  CBLMangoIndexCreator.h
//  CouchbaseLite
//
//  Created by Alexander  Karaberov on 22.02.19.
//

#import <Foundation/Foundation.h>

@class CBLMangoIndex;
@class CBLDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface CBLMangoIndexCreator : NSObject

/**
 Add a single, possibly compound, index for the given field names.
 @returns name of created index
 */
+ (nullable NSString *)ensureIndexed:(CBLMangoIndex *)index
                          inDatabase:(CBLDatabase *)database
                         fromEventDatabase:(CBLDatabase *)eventDatabase;


@end

NS_ASSUME_NONNULL_END
