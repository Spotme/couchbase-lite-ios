//
//  CBLMangoIndexUpdater.m
//  CouchbaseLite
//
//  Created by Alexander  Karaberov on 27.02.19.
//

#import "CBLMangoIndexUpdater.h"
#import "CBLDatabase.h"
#import "CBLDatabase+Internal.h"
#import "FMDatabase.h"
#import "CBLMangoIndexManager.h"

@interface CBLMangoIndexUpdater ()

@property (nonatomic, strong) CBLDatabase *indexDatabase;
@property (nonatomic, strong) CBLDatabase *eventDatabase;

@end


@implementation CBLMangoIndexUpdater

@synthesize indexDatabase = _indexDatabase, eventDatabase = _eventDatabase;

- (instancetype)initWithDatabase:(CBLDatabase *)database eventDatabase:(CBLDatabase *)eventDatabase
{
    self = [super init];
    if (self) {
        _eventDatabase = eventDatabase;
        _indexDatabase = database;
    }
    return self;
}


+ (BOOL)updateIndex:(NSString *)indexName
         withFields:(NSArray<NSString *> *)fieldNames
         inDatabase:(CBLDatabase *)database
  fromEventDatabase:(CBLDatabase *)eventDatabase
              error:(NSError *__nullable __autoreleasing *__nullable)error {
    
    CBLMangoIndexUpdater *indexUpdater = [[CBLMangoIndexUpdater alloc] initWithDatabase:database eventDatabase:eventDatabase];
    BOOL success = [indexUpdater updateIndex:indexName withFields:fieldNames error:error];
    return success;
}


- (BOOL)updateIndex:(NSString *)indexName
         withFields:(NSArray <NSString *> *)fieldNames
              error:(NSError *__autoreleasing *)error
{
    BOOL success = [self updateIndex:indexName
                          fieldNames:fieldNames
                    startingSequence:[self sequenceNumberForIndex:indexName]];
    
    if (!success) {
        if (error) {
            NSDictionary *userInfo = @{
                                       NSLocalizedDescriptionKey : NSLocalizedString(@"Problem updating index.", nil)
                                       };
            *error = [NSError errorWithDomain:kCBLMangoIndexManagerErrorDomain
                                         code:CBLMangoQueryIndexErrorSqlError
                                     userInfo:userInfo];
            LogTo(CBLDatabase, @"Problem updating index %@", indexName);
        }
    }
    return success;
}


- (BOOL)updateIndex:(NSString *)indexName
         fieldNames:(NSArray /* NSString */ *)fieldNames
   startingSequence:(SequenceNumber)lastSequence
{
    __block bool success = YES;
    CBLChangesOptions options = kDefaultCBLChangesOptions;
    options.includeDocs = YES;
    
    CBL_RevisionList* changes = [self.eventDatabase changesSinceSequence:lastSequence
                                                            options:&options
                                                             filter:NULL params: @{}];
    if (changes && changes.allRevisions.count) {
        NSArray *updateBatch = [changes.allRevisions my_filter:^int(id obj) {
            return 1;
        }];
        NSArray *deleteBatch = [changes.allRevisions my_filter:^int(id obj) {
            return 1;
        }];
        if (updateBatch && updateBatch.count) {
            success = success && [self processUpdateBatch:updateBatch];
        }
        if (deleteBatch && deleteBatch.count) {
            success = success && [self processDeleteBatch:deleteBatch];
        }
    }
    return success;
}


- (BOOL)processUpdateBatch:(NSArray *)updateBatch {
    return YES;
}


- (BOOL)processDeleteBatch:(NSArray *)deleteBatch {
    return YES;
}


- (SequenceNumber)sequenceNumberForIndex:(NSString *)indexName
{
    __block SequenceNumber result = 0;
    
    // get current version
    [self.indexDatabase _inTransaction:^CBLStatus{
        NSString *sql = @"SELECT last_sequence FROM %@ WHERE index_name = ?";
        sql = [NSString stringWithFormat:sql, kCBLMangoIndexMetadataTableName];
        CBL_FMResultSet *rs = [self.indexDatabase.fmdb executeQuery:sql withArgumentsInArray:@[indexName]];
        while ([rs next]) {
            result = [rs longLongIntForColumnIndex:0];
            break;  // All rows for a given index will have the same last_sequence, so break
        }
        [rs close];
        
        return kCBLStatusOK;
    }];
    
    return result;
}


@end
