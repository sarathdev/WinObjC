/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#include "Starboard.h"
#include "Foundation/NSString.h"
#include "Foundation/NSURLProtocol.h"
#include "NSURLProtocol_file.h"
#include "NSURLProtocol_http.h"
#include "Foundation/NSMutableArray.h"

static id _registeredClasses = nil;

@implementation NSURLProtocol : NSObject
    /* annotate with type */ +(void) initialize {
        if ( self == [NSURLProtocol class] ) {
            _registeredClasses = [NSMutableArray new];
            [_registeredClasses addObject:[NSURLProtocol_http class]];
            [_registeredClasses addObject:[NSURLProtocol_file class]];
        }
    }

    /* annotate with type */ +(id) _registeredClasses {
        return _registeredClasses;
    }

    +(BOOL) registerClass:(id)cls {
        [_registeredClasses addObject:cls];
        return YES;
    }

    /* annotate with type */ +(id) _URLProtocolClassForRequest:(id)request {
        id classes = [NSURLProtocol _registeredClasses];
        NSInteger count = [classes count];
   
        while(--count>=0){
            id check = [classes objectAtIndex:count];
    
            if( [check canInitWithRequest:request])
                return check;
        }

        id url = [request URL];
        id absStr = [url absoluteString];
        const char* urlStr = [absStr UTF8String];
        EbrDebugLog("Couldn't find protocol handler for %s\n", urlStr ? urlStr : "(nil)");
        //EbrDebugLog("Couldn't find protocol handler\n");
        return nil;
    }

    +(BOOL) _isCustomHandlerForRequest:(id)request {
        id classes = [NSURLProtocol _registeredClasses];
        NSInteger count = [classes count];
   
        while(--count>=0){
            id check = [classes objectAtIndex:count];
    
            if( [check canInitWithRequest:request]) {
                if ( [check class] == [NSURLProtocol_http class] ) {
                    return FALSE;
                }
                return TRUE;
            }
        }

        return FALSE;
    }

    /* annotate with type */ -(id) initWithRequest:(id)request cachedResponse:(id)response client:(id)client {
        _request.attach([request mutableCopy]);
        _cachedResponse = [response retain];
        _client=client;
        return self;
    }

    /* annotate with type */ -(id) client {
        return _client;
    }

    /* annotate with type */ -(id) request {
        return _request;
    }

    /* annotate with type */ -(id) scheduleInRunLoop:(id)runLoop forMode:(id)mode {
        return self;
    }

    /* annotate with type */ -(id) unscheduleFromRunLoop:(id)runLoop forMode:(id)mode {
        return self;
    }

    -(void) dealloc {
        _request = nil;
        [_cachedResponse release];
        [super dealloc];
    }

    
@end

