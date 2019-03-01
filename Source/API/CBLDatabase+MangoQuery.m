//
//  CBLDatabase+MangoQuery.m
//  CouchbaseLite
//
//  Created by Alexander  Karaberov on 01.03.19.
//

#import "CBLDatabase+MangoQuery.h"
#import "CBLMangoIndexManager.h"

@interface CBLDatabase ()

@property (nonatomic, strong, readwrite) CBLMangoIndexManager *mangoIndexManager;

@end

@implementation CBLDatabase (MangoQuery)


- (NSString *)ensureIndexed:(NSArray<NSString *> *)fieldNames
                   withName:(NSString *)indexName
                     ofType:(CBLMangoIndexType)type {
    
    if (!self.mangoIndexManager) {
        NSError *mangoIndexCreationError;
        self.mangoIndexManager = [[CBLMangoIndexManager alloc] initWithDatabase:self error:&mangoIndexCreationError];
        if (mangoIndexCreationError) {
            LogTo(CBLDatabase, @"%@ mango index creation error %@ for fields %@", self, mangoIndexCreationError, fieldNames);
            return nil;
        }
    }
    if (self.mangoIndexManager) {
        return [self.mangoIndexManager ensureIndexed:fieldNames
                                            withName:indexName
                                              ofType:CBLMangoIndexTypeJSON];
    } else {
        LogTo(CBLDatabase, @"%@ failed to create database to support Mango Query indexes", self);
        return nil;
    }
}


- (nullable CBLMangoResultSet *)find:(NSDictionary *)query {
    return nil;
}


- (nullable CBLMangoResultSet *)find:(NSDictionary *)query
                                skip:(NSUInteger)skip
                               limit:(NSUInteger)limit
                              fields:(nullable NSArray *)fields
                                sort:(nullable NSArray *)sortDocument {
    return nil;
}


@end
