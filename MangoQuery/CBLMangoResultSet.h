//
//  CBLMangoResultSet.h
//  CouchbaseLite
//
//  Created by Alexander  Karaberov on 01.03.19.
//

#import <Foundation/Foundation.h>

@class CBLRevision;

NS_ASSUME_NONNULL_BEGIN

@interface CBLMangoResultSet : NSObject

@property (nonatomic, strong, readonly) NSArray<NSString *> *documentIds;


- (void)enumerateObjectsUsingBlock:(void (^)(CBLRevision *rev, NSUInteger idx,
                                             BOOL *stop))block;

@end

NS_ASSUME_NONNULL_END
