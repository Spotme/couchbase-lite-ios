//
//  CBLDatabase+Attachments.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLDatabase+Internal.h"
@class CBL_BlobStoreWriter, CBL_Revision, CBLMultipartWriter;


/** Types of encoding/compression of stored attachments. */
typedef enum {
    kCBLAttachmentEncodingNone,
    kCBLAttachmentEncodingGZIP
} CBLAttachmentEncoding;


@interface CBLDatabase (Attachments)

+ (NSString*) attachmentStorePath: (NSString*)dbPath;
@property (readonly) NSString* attachmentStorePath;

/** Creates a CBL_BlobStoreWriter object that can be used to stream an attachment to the store. */
- (CBL_BlobStoreWriter*) attachmentWriter;

/** Creates CBL_Attachment objects from the revision's '_attachments' property. */
- (NSDictionary*) attachmentsFromRevision: (CBL_Revision*)rev
                                   status: (CBLStatus*)outStatus;

/** Given a newly-added revision, adds the necessary attachment rows to the database and stores inline attachments into the blob store. */
- (CBLStatus) processAttachments: (NSDictionary*)attachments
                    forRevision: (CBL_Revision*)rev
             withParentSequence: (SequenceNumber)parentSequence;

/** Returns whether the revision with this sequence has any attachments. */
- (BOOL) sequenceHasAttachments: (SequenceNumber)sequence;

/** Constructs an "_attachments" dictionary for a revision, to be inserted in its JSON body. */
- (NSDictionary*) getAttachmentDictForSequence: (SequenceNumber)sequence
                                       options: (CBLContentOptions)options;

/** Modifies a CBL_Revision's _attachments dictionary by changing all attachments into stubs.
    Attachments without a "revpos" property will be assigned one with rev's generation. */
+ (void) stubOutAttachments: (NSDictionary*)attachments
                 inRevision: (CBL_MutableRevision*)rev;

/** Modifies a CBL_Revision's _attachments dictionary by changing all attachments with revpos < minRevPos into stubs; and if 'attachmentsFollow' is true, the remaining attachments will be modified to _not_ be stubs but include a "follows" key instead of a body. */
+ (void) stubOutAttachmentsIn: (CBL_MutableRevision*)rev
                 beforeRevPos: (int)minRevPos
            attachmentsFollow: (BOOL)attachmentsFollow;

/** Generates a MIME multipart writer for a revision, with separate body parts for each attachment whose "follows" property is set. */
- (CBLMultipartWriter*) multipartWriterForRevision: (CBL_Revision*)rev
                                      contentType: (NSString*)contentType;

/** Returns the content and metadata of an attachment.
    If you pass NULL for the 'outEncoding' parameter, it signifies that you don't care about encodings and just want the 'real' data, so it'll be decoded for you. */
- (NSData*) getAttachmentForSequence: (SequenceNumber)sequence
                               named: (NSString*)filename
                                type: (NSString**)outType
                            encoding: (CBLAttachmentEncoding*)outEncoding
                              status: (CBLStatus*)outStatus;

/** Returns the location of an attachment's file in the blob store. */
- (NSString*) getAttachmentPathForSequence: (SequenceNumber)sequence
                                     named: (NSString*)filename
                                      type: (NSString**)outType
                                  encoding: (CBLAttachmentEncoding*)outEncoding
                                    status: (CBLStatus*)outStatus;

/** Uses the "digest" field of the attachment dict to look up the attachment in the store and return a file URL to it. DO NOT MODIFY THIS FILE! */
- (NSURL*) fileForAttachmentDict: (NSDictionary*)attachmentDict;

/** Uses the "digest" field of the attachment dict to look up the attachment in the store and return a file data to it. DO NOT MODIFY THIS FILE! */
- (NSData*) fileDataForAttachmentDict: (NSDictionary*)attachmentDict;

/** Deletes obsolete attachments from the database and blob store. */
- (CBLStatus) garbageCollectAttachments;

/** Updates or deletes an attachment, creating a new document revision in the process.
    Used by the PUT / DELETE methods called on attachment URLs. */
- (CBL_Revision*) updateAttachment: (NSString*)filename
                            body: (CBL_BlobStoreWriter*)body
                            type: (NSString*)contentType
                        encoding: (CBLAttachmentEncoding)encoding
                         ofDocID: (NSString*)docID
                           revID: (NSString*)oldRevID
                          status: (CBLStatus*)outStatus;
@end
