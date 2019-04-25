//
//  CBLMangoIndex.m
//  CouchbaseLite
//
//  Created by Alexander  Karaberov on 22.02.19.
//

#import "CBLMangoIndex.h"
#import "CBLMangoIndexManager.h"

@implementation CBLMangoIndex

@synthesize fieldNames = _fieldNames, indexName = _indexName, type = _type, indexSettings = _indexSettings;

- (instancetype)initWithFields:(NSArray *)fieldNames
                     indexName:(NSString *)indexName
                     indexType:(CBLMangoIndexType)indexType
                 indexSettings:(NSDictionary *)indexSettings
{
    self = [super init];
    if (self) {
        _fieldNames = fieldNames;
        _indexName = indexName;
        _type = indexType;
        _indexSettings = indexSettings;
    }
    return self;
}

+ (instancetype)index:(NSString *)indexName
           withFields:(NSArray<NSString *> *)fieldNames
                 type:(CBLMangoIndexType)type
{
    return [[self class] index:indexName withFields:fieldNames type:type withSettings:nil];
}

+ (instancetype)index:(NSString *)indexName
           withFields:(NSArray *)fieldNames
                 type:(CBLMangoIndexType)indexType
         withSettings:(NSDictionary *)indexSettings
{
    if (fieldNames.count == 0) {
        NSLog(@"No field names provided.");
        return nil;
    }
    
    if (indexName.length == 0) {
        indexName = [[[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
    }

    
    return [[[self class] alloc] initWithFields:fieldNames
                                      indexName:indexName
                                      indexType:indexType
                                  indexSettings:indexSettings];
}

@end
