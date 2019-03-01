//
//  CBLDatabase+MangoQuery.h
//  CouchbaseLite
//
//  Created by Alexander  Karaberov on 01.03.19.
//

#import <CouchbaseLite/CouchbaseLite.h>
#import "CBLMangoIndexManager.h"
#import "CBLMangoResultSet.h"


NS_ASSUME_NONNULL_BEGIN

@interface CBLDatabase (MangoQuery)


/**
  Creates an index on the specified field if the index does not already exist.
  Naming conventions are similar to the MongoDB
 */
- (NSString *)ensureIndexed:(NSArray<NSString *> *)fieldNames
                   withName:(NSString *)indexName
                     ofType:(CBLMangoIndexType)type;

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
