//
//  CBLMangoIndexManager.m
//
//  Created by Mike Rhodes on 2014-09-27
//
//  Copyright © 2018 IBM Corporation. All rights reserved.
//  Copyright (c) 2014 Cloudant. All rights reserved.
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


//
// The metadata for an index is represented in the database table as follows:
//
//   index_name  |  index_type  |  field_name  |  last_sequence
//   -----------------------------------------------------------
//     name      |  json        |   _id        |     0
//     name      |  json        |   _rev       |     0
//     name      |  json        |   firstName  |     0
//     name      |  json        |   lastName   |     0
//     age       |  json        |   age        |     0
//
// The index itself is a single table, with a colum for docId and each of the indexed fields:
//
//      _id      |   _rev      |  firstName   |  lastName
//   --------------------------------------------------------
//     miker     |  1-blah     |  Mike        |  Rhodes
//     johna     |  3-blob     |  John        |  Appleseed
//     joeb      |  2-blip     |  Joe         |  Bloggs
//
// There is a single SQLite index created on all columns of this table.
//
// N.b.: _id and _rev are automatically added to all indexes to allow them to be used to
// project CDTDocumentRevisions without the need to load a document from the datastore.
//

#import "CBLMangoIndexManager.h"
#import "CBLDatabase.h"
#import "CBLMangoIndex.h"
#import "CBLMangoIndexCreator.h"
#import "CBLDatabase+Internal.h"
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"

NSString *const kCBLMangoIndexManagerErrorDomain = @"CBLMangoIndexManagerErrorDomain";
NSString *const kCBLMangoIndexTablePrefix = @"_t_cbl__mango_query_index_";
NSString *const kCBLMangoIndexMetadataTableName = @"_t_cbl__mango_query_metadata";


static NSString *const kCBLMangoQueryExtensionName = @"com.cbl.mango.query";
static NSString *const kCBLMangoQueryIndexRoot = @"_mango_indexes";
static NSString *const kCBLMangoIndexFieldNamePattern = @"^[a-zA-Z][a-zA-Z0-9_]*$";

//static const int VERSION = 1;

@interface CBLMangoIndexManager ()

@property (nonatomic, strong) NSRegularExpression *validFieldName;
@property (nonatomic, strong) CBL_FMDatabase *database;

@end


@implementation CBLMangoQuerySqlParts

@synthesize sqlWithPlaceholders = _sqlWithPlaceholders, placeholderValues = _placeholderValues;

+ (CBLMangoQuerySqlParts *)partsForSql:(NSString *)sql parameters:(NSArray *)parameters
{
    CBLMangoQuerySqlParts *parts = [CBLMangoQuerySqlParts new];
    parts.sqlWithPlaceholders = sql;
    parts.placeholderValues = parameters;
    return parts;
}

- (NSString *)description
{
    return [NSString
            stringWithFormat:@"sql: %@ vals: %@", self.sqlWithPlaceholders, self.placeholderValues];
}

@end

@implementation CBLMangoIndexManager

@synthesize validFieldName = _validFieldName, database =_database;


- (nullable CBLMangoIndexManager *)initWithDatabase:(CBLDatabase *)database error:(NSError *__autoreleasing *)error
{
    self = [super init];
    if (self) {
        if (database.name && database.path) {
            NSString *indexDir = [NSString pathWithComponents:@[database.path,
                                                                [NSString stringWithFormat:@"%@%@", database.name, kCBLMangoQueryIndexRoot],
                                                                kCBLMangoQueryExtensionName]];
            [[NSFileManager defaultManager] createDirectoryAtPath:indexDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
            NSString *filename = [NSString pathWithComponents:@[indexDir, @"mango-indexes.sqlite" ]];
            
            _database = [[CBL_FMDatabase alloc] initWithPath:filename];
            if (_database) {
                _validFieldName = [[NSRegularExpression alloc] initWithPattern:kCBLMangoIndexFieldNamePattern
                                                                       options:0
                                                                         error:error];
            } else {
                self = nil;
            }
        } else {
            self = nil;
        }
    }
    return self;
}


- (void)dealloc
{
    // close the database.
    //CDTLogDebug(CDTQ_LOGGING_CONTEXT, @"-dealloc CDTQIndexManager %@", self);
    //[self.database close];
}

#pragma mark List indexes

/**
 Returns:
 
 { indexName: { type: json,
 name: indexName,
 fields: [field1, field2]
 }
 */
- (NSDictionary<NSString *, NSArray<NSString *> *> *)listIndexes
{
    return @{};
}


#pragma mark Create Indexes

- (NSString *)ensureIndexed:(NSArray<NSString *> *)fieldNames
                   withName:(NSString *)indexName
                     ofType:(CBLMangoIndexType)type
{
    CBLMangoIndex *mangoIndex = [CBLMangoIndex index:indexName
                                          withFields:fieldNames
                                                type:type];
    return [CBLMangoIndexCreator ensureIndexed:mangoIndex inDatabase:self.database];
}


#pragma mark Delete Indexes

- (BOOL)deleteIndexNamed:(NSString *)indexName
{
    __block BOOL success = YES;
    
    //    [_database inTransaction:^(FMDatabase *db, BOOL *rollback) {
    //
    //        NSString *tableName = [CDTQIndexManager tableNameForIndex:indexName];
    //        NSString *sql;
    //
    //        // Drop the index table
    //        sql = [NSString stringWithFormat:@"DROP TABLE \"%@\";", tableName];
    //        success = success && [db executeUpdate:sql withArgumentsInArray:@[]];
    //
    //        // Delete the metadata entries
    //        sql = [NSString
    //            stringWithFormat:@"DELETE FROM %@ WHERE index_name = ?", kCDTQIndexMetadataTableName];
    //        success = success && [db executeUpdate:sql withArgumentsInArray:@[ indexName ]];
    //
    //        if (!success) {
    //            CDTLogError(CDTQ_LOG_CONTEXT, @"Failed to delete index: %@", indexName);
    //            *rollback = YES;
    //        }
    //    }];
    
    return success;
}

#pragma mark Update indexes

- (BOOL)updateAllIndexes
{
    // TODO
    
    // To start with, assume top-level fields only
    return NO;
    //    NSDictionary *indexes = [self listIndexes];
    //    return
    //        [CDTQIndexUpdater updateAllIndexes:indexes inDatabase:_database fromDatastore:_datastore];
}

#pragma mark Query indexes


#pragma mark Utilities

+ (NSString *)tableNameForIndex:(NSString *)indexName
{
    return [kCBLMangoIndexTablePrefix stringByAppendingString:indexName];
}


@end

