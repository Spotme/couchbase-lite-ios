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
#import "CBLMangoIndexUpdater.h"
#import "CBLManager.h"


@interface CBLMangoIndexCreator ()

@property(nonatomic, strong) CBLDatabase *eventDatabase;
@property(nonatomic, strong) CBLDatabase *indexDatabase;

@end


@implementation CBLMangoIndexCreator

@synthesize eventDatabase = _eventDatabase, indexDatabase = _indexDatabase;


- (instancetype)initWithDatabase:(CBLDatabase *)indexDatabase eventDatabase:(CBLDatabase *)eventDatabase;
{
    self = [super init];
    if (self) {
        _indexDatabase = indexDatabase;
        _eventDatabase = eventDatabase;
    }
    return self;
}


+ (nullable NSString *)ensureIndexed:(CBLMangoIndex *)index
                          inDatabase:(CBLDatabase *)database
                   fromEventDatabase:(CBLDatabase *)eventDatabase {
    
    CBLMangoIndexCreator *creator =  [[CBLMangoIndexCreator alloc] initWithDatabase:database eventDatabase:eventDatabase];
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
    CBLStatus status = [self.indexDatabase _inTransaction: ^CBLStatus {
        NSArray *inserts = [CBLMangoIndexCreator insertMetadataStatementsForIndexName:index.indexName
                                                                                 type:@"json"
                                                                             settings:@""
                                                                           fieldNames:index.fieldNames];
        for (CBLMangoQuerySqlParts *sql in inserts) {
            success = success && [self.indexDatabase.fmdb executeUpdate:sql.sqlWithPlaceholders
                                                   withArgumentsInArray:sql.placeholderValues];
        }
        
        // Create SQLite data structures to support the index
        // For JSON index type create a SQLite table and a SQLite index
        CBLMangoQuerySqlParts *createTable = [CBLMangoIndexCreator createIndexTableStatementForIndexName:index.indexName
                                                                                              fieldNames:fieldNames];
        success = success && [self.indexDatabase.fmdb executeUpdate:createTable.sqlWithPlaceholders
                                               withArgumentsInArray:createTable.placeholderValues];
        
        // Create the SQLite index on the index table
        CBLMangoQuerySqlParts *createIndex = [CBLMangoIndexCreator createIndexIndexStatementForIndexName:index.indexName
                                                                                              fieldNames:fieldNames];
        success = success && [self.indexDatabase.fmdb executeUpdate:createIndex.sqlWithPlaceholders
                                               withArgumentsInArray:createIndex.placeholderValues];
        
        CBLStatus status = kCBLStatusBadJSON;
        if (success) {
            status = kCBLStatusCreated;
        }
        return status;
    }];
    // Update the new index if it's been created
    if (success && !CBLStatusIsError(status)) {
        success = success && [CBLMangoIndexUpdater updateIndex:index.indexName
                                                    withFields:index.fieldNames
                                                    inDatabase:self.indexDatabase
                                             fromEventDatabase:self.eventDatabase
                                                         error:nil];
    }
    
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


+ (CBLMangoQuerySqlParts *)createIndexTableStatementForIndexName:(NSString *)indexName
                                             fieldNames:(NSArray *)fieldNames
{
    if (!indexName) {
        return nil;
    }
    
    if (!fieldNames || fieldNames.count == 0) {
        return nil;
    }
    
    NSString *tableName = [CBLMangoIndexManager tableNameForIndex:indexName];
    NSMutableArray *clauses = [NSMutableArray array];
    for (NSString *fieldName in fieldNames) {
        NSString *clause = [NSString stringWithFormat:@"\"%@\" NONE", fieldName];
        [clauses addObject:clause];
    }
    
    NSString *sql = [NSString stringWithFormat:@"CREATE TABLE \"%@\" ( %@ );", tableName,
                     [clauses componentsJoinedByString:@", "]];
    return [CBLMangoQuerySqlParts partsForSql:sql parameters:@[]];
}


+ (CBLMangoQuerySqlParts *)createIndexIndexStatementForIndexName:(NSString *)indexName
                                             fieldNames:(NSArray *)fieldNames
{
    if (!indexName) {
        return nil;
    }
    
    if (!fieldNames || fieldNames.count == 0) {
        return nil;
    }
    
    NSString *tableName = [CBLMangoIndexManager tableNameForIndex:indexName];
    NSString *sqlIndexName = [tableName stringByAppendingString:@"_index"];
    
    NSMutableArray *clauses = [NSMutableArray array];
    for (NSString *fieldName in fieldNames) {
        [clauses addObject:[NSString stringWithFormat:@"\"%@\"", fieldName]];
    }
    
    NSString *sql =
    [NSString stringWithFormat:@"CREATE INDEX \"%@\" ON \"%@\" ( %@ );", sqlIndexName,
     tableName, [clauses componentsJoinedByString:@", "]];
    return [CBLMangoQuerySqlParts partsForSql:sql parameters:@[]];
}


@end
