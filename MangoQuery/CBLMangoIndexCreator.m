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
#import "CBLMangoIndexManager.h"


@interface CBLMangoIndexCreator ()

@property(nonatomic, strong) CBLDatabase *database;

@end


@implementation CBLMangoIndexCreator

@synthesize database = _database;

- (instancetype)initWithDatabase:(CBLDatabase *)database
{
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}


+ (nullable NSString *)ensureIndexed:(CBLMangoIndex *)index
                          inDatabase:(CBLDatabase *)database {
    
    CBLMangoIndexCreator *creator =  [[CBLMangoIndexCreator alloc] initWithDatabase:database];
    return [creator ensureIndexed:index];
}


- (NSString *)ensureIndexed:(CBLMangoIndex *)index
{
    if (!index) {
        return nil;
    }
    NSArray *fieldNames = [CBLMangoIndexCreator removeDirectionsFromFields:index.fieldNames];
    
    if (![fieldNames containsObject:@"_rev"]) {
        NSMutableArray *tmp = [NSMutableArray arrayWithObject:@"_rev"];
        [tmp addObjectsFromArray:fieldNames];
        fieldNames = [NSArray arrayWithArray:tmp];
    }
    
    if (![fieldNames containsObject:@"_id"]) {
        NSMutableArray *tmp = [NSMutableArray arrayWithObject:@"_id"];
        [tmp addObjectsFromArray:fieldNames];
        fieldNames = [NSArray arrayWithArray:tmp];
    }
    
    __block BOOL success = YES;
    [self.database _inTransaction:^CBLStatus{
        NSArray *inserts = [CBLMangoIndexCreator insertMetadataStatementsForIndexName:index.indexName
                                                                                 type:@"json"
                                                                             settings:@""
                                                                           fieldNames:index.fieldNames];
        for (CBLMangoQuerySqlParts *sql in inserts) {
            success = success && [self.database.fmdb executeUpdate:sql.sqlWithPlaceholders
                                              withArgumentsInArray:sql.placeholderValues];
        }
        // TODO
        // Create SQLite data structures to support the index
        // For JSON index type create a SQLite table and a SQLite index
//        CBLMangoQuerySqlParts *createTable =
//        [CBLMangoIndexCreator createIndexTableStatementForIndexName:index.indexName
//                                                     fieldNames:fieldNames];
//        success = success && [self.database.fmdb executeUpdate:createTable.sqlWithPlaceholders
//                          withArgumentsInArray:createTable.placeholderValues];
//
//        // Create the SQLite index on the index table
//
//        CBLMangoQuerySqlParts *createIndex =
//        [CBLMangoIndexCreator createIndexIndexStatementForIndexName:index.indexName
//                                                     fieldNames:fieldNames];
//        success = success && [self.database.fmdb executeUpdate:createIndex.sqlWithPlaceholders
//                                          withArgumentsInArray:createIndex.placeholderValues];

        CBLStatus status = kCBLStatusBadJSON;
        if (success) {
            status = kCBLStatusCreated;
        }
        return status;
    }];
    
    //    // Update the new index if it's been created
    //    if (success) {
    //        success = success && [CDTQIndexUpdater updateIndex:index.indexName
    //                                                withFields:fieldNames
    //                                                inDatabase:_database
    //                                             fromDatastore:_datastore
    //                                                     error:nil];
    //    }
    
    return success ? index.indexName : nil;
}


+ (NSArray *)removeDirectionsFromFields:(NSArray *)fieldNames
{
    NSMutableArray *result = [NSMutableArray array];
    
    for (NSObject *field in fieldNames) {
        if ([field isKindOfClass:[NSDictionary class]]) {
            NSDictionary *specifier = (NSDictionary *)field;
            if (specifier.count == 1) {
                NSString *fieldName = [specifier allKeys][0];
                [result addObject:fieldName];
            }
        } else if ([field isKindOfClass:[NSString class]]) {
            [result addObject:field];
        }
    }
    
    return result;
}


+ (NSArray *)insertMetadataStatementsForIndexName:(NSString *)indexName
                                             type:(NSString *)indexType
                                         settings:(NSString *)indexSettings
                                       fieldNames:(NSArray *)fieldNames
{
    if (!indexName) {
        return nil;
    }
    
    if (!fieldNames || fieldNames.count == 0) {
        return nil;
    }
    
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *fieldName in fieldNames) {
        NSString *sql;
        NSArray *metaParameters;
        if (indexSettings) {
            sql = @"INSERT INTO %@"
            " (index_name, index_type, index_settings, field_name, last_sequence) "
            "VALUES (?, ?, ?, ?, 0);";
            metaParameters = @[ indexName, indexType, indexSettings, fieldName ];
        } else {
            sql = @"INSERT INTO %@"
            " (index_name, index_type, field_name, last_sequence) "
            "VALUES (?, ?, ?, 0);";
            metaParameters = @[ indexName, indexType, fieldName ];
        }
        sql = [NSString stringWithFormat:sql, kCBLMangoIndexMetadataTableName];
        
        CBLMangoQuerySqlParts *parts = [CBLMangoQuerySqlParts partsForSql:sql parameters:metaParameters];
        [result addObject:parts];
    }
    return result;
}

@end
