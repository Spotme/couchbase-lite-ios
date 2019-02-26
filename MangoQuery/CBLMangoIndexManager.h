//
//  CBLMangoIndexManager.h
//
//  Created by Mike Rhodes on 2014-09-27
//  Copyright (c) 2014 Cloudant. All rights reserved.
//  Copyright © 2018 IBM Corporation. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.


//  Modified by Oleksandr Karaberov on 2019-02-21
//
//  Copyright © 2019 SpotMe Engineering. All rights reserved.


#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class CBLDatabase;

extern NSString *const kCBLMangoIndexManagerErrorDomain;
extern NSString *const kCBLMangoIndexTablePrefix;
extern NSString *const kCBLMangoIndexMetadataTableName;


/**
 * Query Index types
 */
typedef NS_ENUM(NSUInteger, CBLMangoIndexType) {
    /**
     * Denotes the index is of type text.
     */
    //    CBLMangoIndexTypeText,
    /**
     * Denotes the index of type JSON.
     */
    CBLMangoIndexTypeJSON
    
};

@interface CBLMangoQuerySqlParts : NSObject

@property (nonatomic, strong) NSString *sqlWithPlaceholders;
@property (nonatomic, strong) NSArray *placeholderValues;

+ (CBLMangoQuerySqlParts *)partsForSql:(NSString *)sql parameters:(NSArray *)parameters;

@end

/**
 * Indexing and query erors.
 */
typedef NS_ENUM(NSInteger, CBLMangoQueryError) {
    /**
     * Index name not valid. Names can only contain letters,
     * digits and underscores. They must not start with a digit.
     */
    CBLMangoQueryIndexErrorInvalidIndexName = 1,
    /**
     * An SQL error occurred during indexing or querying.
     */
    CBLMangoQueryIndexErrorSqlError = 2,
    /**
     * No index with this name was found.
     */
    CCBLMangoQueryIndexErrorIndexDoesNotExist = 3,
    /**
     * Key provided could not be used to initialize index manager
     */
    CBLMangoQueryIndexErrorEncryptionKeyError = 4
};

/**
 Main interface to Mango query.
 
 Use the manager to:
 
 - create indexes
 - delete indexes
 - execute queries
 - update indexes (usually done automatically)
 */
@interface CBLMangoIndexManager : NSObject


/**
 Constructs a new CBLMangoIndexManager which indexes documents in database
 */
- (nullable CBLMangoIndexManager *)initWithDatabase:(CBLDatabase *)database
                                              error:(NSError *__autoreleasing *)error;


- (NSDictionary<NSString *, NSArray<NSString *> *> *)listIndexes;

- (NSString *)ensureIndexed:(NSArray<NSString *> *)fieldNames
                   withName:(NSString *)indexName
                     ofType:(CBLMangoIndexType)type;


- (BOOL)deleteIndexNamed:(NSString *)indexName;

- (BOOL)updateAllIndexes;

+ (NSString *)tableNameForIndex:(NSString *)indexName;


@end


NS_ASSUME_NONNULL_END

