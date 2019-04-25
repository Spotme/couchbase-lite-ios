//
//  CBLMangoResultSet.m
//  CouchbaseLite
//
//  Created by Alexander  Karaberov on 01.03.19.
//

#import "CBLMangoResultSet.h"
#import "CBLRevision.h"

@interface CBLMangoResultSet ()

@property (nonatomic, strong, readwrite) NSArray<NSString *> *documentIds;

@end

@implementation CBLMangoResultSet

@synthesize documentIds = _documentIds;


- (void)enumerateObjectsUsingBlock:(void (^)(CBLRevision *rev, NSUInteger idx,
                                             BOOL *stop))block
{
    //TODO: Iterator over result set
}

@end
