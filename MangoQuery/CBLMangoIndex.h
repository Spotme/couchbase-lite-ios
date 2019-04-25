//
//  CBLMangoIndex.h
//  CouchbaseLite
//
//  Created by Alexander  Karaberov on 22.02.19.
//

#import <Foundation/Foundation.h>
#import "CBLMangoIndexManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLMangoIndex : NSObject

@property (nullable, nonatomic, strong) NSArray<NSString *> *fieldNames;
@property (nonatomic, strong) NSString *indexName;
@property (nullable, nonatomic, strong) NSDictionary *indexSettings;
@property (nonatomic) CBLMangoIndexType type;


+ (instancetype)index:(NSString *)indexName
           withFields:(NSArray<NSString *> *)fieldNames
                 type:(CBLMangoIndexType)type;

@end

NS_ASSUME_NONNULL_END
