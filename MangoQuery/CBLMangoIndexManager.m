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
#import "CBLManager.h"
#import "FMDatabase.h"
#import "FMResultSet.h"
#import "CBLManager+Internal.h"

char * const kCBLMangoIndexManagerDispatchQueueName = "com.spotme.CouchbaseLite.MangoQueryQ";
NSString * const kCBLMangoIndexManagerErrorDomain = @"CBLMangoIndexManagerErrorDomain";
NSString * const kCBLMangoIndexTablePrefix = @"t_cbl__mango_query_index_";
NSString * const kCBLMangoIndexMetadataTableName = @"t_cbl__mango_query_metadata";


static NSString * const kCBLMangoQueryExtensionName = @"com.cbl.mango.query";
static NSString * const kCBLMangoQueryIndexRoot = @"_mango_indexes";
static NSString * const kCBLMangoIndexFieldNamePattern = @"^[a-zA-Z][a-zA-Z0-9_]*$";

static const int INDEX_DB_VERSION = 1;

@interface CBLMangoIndexManager ()


@property (nonatomic, strong, readwrite) dispatch_queue_t mangoQueryEngineDispatchQueue;
@property (nonatomic, strong) NSRegularExpression *validFieldName;
@property (nonatomic, weak) CBLDatabase *eventDatabase;
@property (nonatomic, strong, readwrite) CBLManager *mangoBackgoundCblManager;
@property (nonatomic, strong, readwrite) CBLDatabase *indexDatabase;

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

@synthesize validFieldName = _validFieldName, eventDatabase =_eventDatabase, indexDatabase = _indexDatabase,
mangoQueryEngineDispatchQueue = _mangoQueryEngineDispatchQueue, mangoBackgoundCblManager = _mangoBackgoundCblManager;


- (nullable CBLMangoIndexManager *)initWithDatabase:(CBLDatabase *)database
{
    self = [super init];
    if (self) {
        if (database && database.name) {
            _mangoQueryEngineDispatchQueue = dispatch_queue_create(kCBLMangoIndexManagerDispatchQueueName, NULL);
            _mangoBackgoundCblManager = [[CBLManager sharedInstance] copy];
            _mangoBackgoundCblManager.dispatchQueue = _mangoQueryEngineDispatchQueue;
            _eventDatabase = database;
            dispatch_async(_mangoQueryEngineDispatchQueue, ^{
                BOOL success = NO;
                NSError *creationError;
                NSString *indexDbName = [CBLMangoIndexManager indexDatabaseNameForDatabaseName:database.name];
                _indexDatabase = [_mangoBackgoundCblManager _databaseNamed:indexDbName
                                                                 mustExist:NO
                                                                 error:&creationError];
                // Workaround for a thread safety check in [FMDB beginUse]
                // The best option would be to skip a check for dispatch_get_current_queue() in the FMDB completely
                // because there is no way to inspect dispatch_queue invocation tree with the public libdispatch API.
                // Exactly the same has been done in the upstrem:
                // https://github.com/couchbaselabs/fmdb/commit/9838b4a49e10ebdefbda706df51273e80198dc59
                // But so that not to modify FMDB submodule let's keep this workaround for now
                [_indexDatabase.fmdb setDispatchQueue:_mangoQueryEngineDispatchQueue];
                if (_indexDatabase && !creationError) {
                    NSError *openError;
                    BOOL result = [_indexDatabase openFMDB:&openError];
                    if (result && !openError) {
                        success = [CBLMangoIndexManager updateSchema:INDEX_DB_VERSION inDatabase:_indexDatabase];
                    }
                }
                if (!success) {
                    [_indexDatabase close];
                }
            });
            __autoreleasing NSError *regExpError;
            _validFieldName = [[NSRegularExpression alloc] initWithPattern:kCBLMangoIndexFieldNamePattern
                                                                   options:0
                                                                     error:&regExpError];
        } else {
            self = nil;
        }
    }
    return self;
}


- (void)dealloc
{
    [self.indexDatabase close];
}

#pragma mark List indexes

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)listIndexesInDatabase:(CBLDatabase *)indexDatabase
{
    NSMutableDictionary *indexes = [NSMutableDictionary dictionary];
    
    NSString *sql = @"SELECT index_name, index_type, field_name, index_settings FROM %@;";
    sql = [NSString stringWithFormat:sql, kCBLMangoIndexMetadataTableName];
    CBL_FMResultSet *rs = [indexDatabase.fmdb executeQuery:sql];
    while ([rs next]) {
        NSString *rowIndex = [rs stringForColumnIndex:0];
        NSString *rowType = [rs stringForColumnIndex:1];
        NSString *rowField = [rs stringForColumnIndex:2];
        NSString *rowSettings = [rs stringForColumnIndex:3];
        
        if (indexes[rowIndex] == nil) {
            if (rowSettings) {
                indexes[rowIndex] = @{@"type" : rowType,
                                      @"name" : rowIndex,
                                      @"fields" : [NSMutableArray array],
                                      @"settings" : rowSettings};
            } else {
                indexes[rowIndex] = @{@"type" : rowType,
                                      @"name" : rowIndex,
                                      @"fields" : [NSMutableArray array]};
            }
        }
        
        [indexes[rowIndex][@"fields"] addObject:rowField];
    }
    [rs close];
    
    // Now we need to make the return value immutable
    
    for (NSString *indexName in [indexes allKeys]) {
        NSMutableDictionary *details = indexes[indexName];
        if (details[@"settings"]) {
            indexes[indexName] = @{
                                   @"type" : details[@"type"],
                                   @"name" : details[@"name"],
                                   @"fields" : [details[@"fields"] copy],  // -copy makes arrays immutable
                                   @"settings" : details[@"settings"]
                                   };
        } else {
            indexes[indexName] = @{
                                   @"type" : details[@"type"],
                                   @"name" : details[@"name"],
                                   @"fields" : [details[@"fields"] copy]  // -copy makes arrays immutable
                                   };
        }
    }
    
    return [NSDictionary dictionaryWithDictionary:indexes];
}


#pragma mark Create Indexes

- (NSString *)ensureIndexed:(NSArray<NSString *> *)fieldNames
                   withName:(NSString *)indexName
                     ofType:(CBLMangoIndexType)type
{
    CBLMangoIndex *mangoIndex = [CBLMangoIndex index:indexName
                                          withFields:fieldNames
                                                type:type];
    if (mangoIndex) {
        return [CBLMangoIndexCreator ensureIndexed:mangoIndex
                                        inDatabase:self.indexDatabase
                                 fromEventDatabase:self.eventDatabase];
    }
    return nil;
}


#pragma mark Utilities

+ (nonnull NSString *)indexDatabaseNameForDatabaseName:(nonnull NSString *)databaseName {
    return  [NSString stringWithFormat:@"%@_%@", databaseName, @"mango-indexes"];
}


+ (nonnull NSString *)eventDatabaseNameForIndexDatabaseName:(nonnull NSString *)databaseName {
    return [databaseName stringByReplacingOccurrencesOfString:@"_mango-indexes" withString:@""];
}


+ (NSString *)tableNameForIndex:(NSString *)indexName
{
    return [kCBLMangoIndexTablePrefix stringByAppendingString:indexName];
}


+ (BOOL)updateSchema:(int)currentVersion inDatabase:(CBLDatabase *)database {
    
    CBLStatus status = [database _inTransaction:^CBLStatus{
        int version = 0;
        CBL_FMResultSet *rs = [database.fmdb executeQuery:@"pragma user_version;"];
        while ([rs next]) {
            version = [rs intForColumnIndex:0];
            break;
        }
        [rs close];
        [database.fmdb executeUpdate:@"BEGIN TRANSACTION"];
        NSString *metadataSchema = [NSString stringWithFormat:@"CREATE TABLE %@ ( "
                                    @"        index_name TEXT NOT NULL, " @" index_type TEXT NOT NULL, "
                                    @"        index_settings TEXT NULL, "
                                    @"        field_name TEXT NOT NULL, " @" last_sequence INTEGER NOT NULL);", kCBLMangoIndexMetadataTableName];
        
        if ([database.fmdb executeUpdate:metadataSchema]) {
            [database.fmdb executeUpdate:@"END TRANSACTION"];
            return kCBLStatusOK;
        } else {
            [database close];
            return kCBLStatusDBError;
        }
    }];
    if (!CBLStatusIsError(status)) {
        return YES;
    }
    return NO;
}

@end

