//
//  CBLDatabase+MangoQuery.h
//  CouchbaseLite
//
//  Created by Alexander  Karaberov on 01.03.19.
//

#import "CBLDatabase.h"
#import "CBLMangoIndexManager.h"
#import "CBLMangoResultSet.h"


NS_ASSUME_NONNULL_BEGIN

typedef void(^MangoIndexCompletionBlock)(NSString * _Nullable index);

@interface CBLDatabase (MangoQuery)

@property (nonatomic, strong) CBLMangoIndexManager *mangoIndexManager;

/**
 @description Initialises Mango query engine and creates a Mango indexes database.
 @warning Must be called on the main UI thread otherwise an exception will be thrown
 @note All Mango indexes operations are performed on a separate backgound queue
 */
- (BOOL)activateMangoQueryEngine;

/**
  Creates an index on the specified field if the index does not already exist.
  Naming conventions are similar to the MongoDB ones.
 */
- (void)ensureIndexed:(NSArray<NSString *> *)fieldNames
                   withName:(NSString *)indexName
                     ofType:(CBLMangoIndexType)type
          completionHandler:(MangoIndexCompletionBlock)completion;

/**
 Find documents matching a query.
 
 See -find:skip:limit:fields:sort: for more details.
 
 Failures during query (e.g., invalid query) are logged rather than
 error being returned.
 
 @return Set of documents, or `nil` if there was an error.
 */
- (nullable CBLMangoResultSet *)find:(NSDictionary *)query;

/**
 Find document matching a query.
 
 See http://docs.couchdb.org/en/2.3.1/api/database/find.html#
 Or https://docs.mongodb.com/manual/reference/method/db.collection.find/
 for details of the query syntax and option meanings.
 
 @return Set of documents, or `nil` if there was an error.
 */
- (nullable CBLMangoResultSet *)find:(NSDictionary *)query
                            skip:(NSUInteger)skip
                           limit:(NSUInteger)limit
                          fields:(nullable NSArray *)fields
                            sort:(nullable NSArray *)sortDocument;

@end

NS_ASSUME_NONNULL_END
