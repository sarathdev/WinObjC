/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#include "Starboard.h"

#include "CoreFoundation/CFDictionary.h"

#include "Foundation/NSDictionary.h"
#include "Foundation/NSString.h"
#include "Foundation/NSNumber.h"
#include "Foundation/NSKeyedUnarchiver.h"
#include "Foundation/NSMutableArray.h"
#include "Foundation/NSMutableDictionary.h"
#include "Foundation/NSData.h"
#include "Foundation/NSValue.h"
#include "NSPropertyListReader.h"
#include "NSXMLPropertyList.h"

static IWLazyClassLookup _LazyUIClassSwapper("UIClassSwapper");

@implementation NSKeyedUnarchiver : NSCoder
    -(instancetype) initForReadingWithData:(NSData*)data {
        if ( data == nil ) return nil;

        _nameToReplacementClass.attach([NSMutableDictionary new]);

        char *bytes = (char *) [data bytes];
        if ( memcmp(bytes, "<?xml", 5) == 0 ) {
            bool returnNow = false;

            if ( returnNow ) return nil;
            _propertyList = [NSXMLPropertyList propertyListFromData:data];
        } else {
            NSPropertyListReaderA read;
            read.init(data);
            _propertyList = read.read();
        }
        _objects = [_propertyList objectForKey:@"$objects"];
        _plistStack.attach([NSMutableArray new]);

        if ( [_propertyList objectForKey:@"$top"] != nil ) {
            [_plistStack addObject:[_propertyList objectForKey:@"$top"]];
        }

        _uidToObject.attach((NSDictionary*) CFDictionaryCreateMutable(nil, 128, &kCFTypeDictionaryKeyCallBacks, NULL));

        _dataObjects.attach([NSMutableArray new]);

        return self;
    }

    static id decodeClassFromDictionary(NSKeyedUnarchiver* self, id classReference)
    {
        id plist   = [classReference objectForKey:@"$class"];
        id uid     = [plist objectForKey:@"CF$UID"];
        id profile = [self->_objects objectAtIndex:[uid intValue]];
        id classes = [profile objectForKey:@"$classes"];
        id className = [profile objectForKey:@"$classname"];

        return className;
    }

    static id decodeObjectForUID(NSKeyedUnarchiver* self, NSNumber* uid)
    {
        DWORD uidIntValue = [uid intValue];
        id result = [self->_uidToObject objectForKey:uid];

        if(result==NULL)
        {
            id plist = [self->_objects objectAtIndex:uidIntValue];

            if([plist isKindOfClass:[NSString class]])
            {
                if([plist isEqualToString:@"$null"])
                    result=NULL;
                else {
                    result=plist;
                    [self->_uidToObject setObject:result forKey:uid];
                }
            } else if([plist isKindOfClass:[NSDictionary class]])
            {
                id className = decodeClassFromDictionary(self, plist);

                const char *pClassName = [className UTF8String];

                static int indentCount = 0;

                [self->_plistStack addObject:plist];

                id classType = objc_getClass(pClassName);

                if ( classType != nil ) {
                    result = [classType alloc];

                    if ( [result isKindOfClass:[_LazyUIClassSwapper class]] ) {
                        [self->_uidToObject setObject:result forKey:uid];

                        int curPos = self->_curUid;

                        self->_curUid = 0;

                        id orig = result;
                        result = [result instantiateWithCoder:self];
                        [orig autorelease];

                        self->_curUid = curPos;
                    }

                    [self->_uidToObject setObject:result forKey:uid];

                    int curPos = self->_curUid;

                    self->_curUid = 0;
                    if ( [result respondsToSelector:@selector(initWithCoder:)] ) {
                        result = [result initWithCoder:self];
                    } else {
                        if ( result != nil ) EbrDebugLog("%s does not respond to initWithCoder\n", object_getClassName(result));
                    }

                    self->_curUid = curPos;

                    if ( result != nil ) {
                        [self->_uidToObject setObject:result forKey:uid];
                        if ( [result respondsToSelector:@selector(awakeAfterUsingCoder:)] ) {
                            result = [result awakeAfterUsingCoder:self];
                        }

                        [result autorelease];
                        [self->_uidToObject setObject:result forKey:uid];
                    } else {
                        EbrDebugLog("NSKeyedUnarchiver: Object initialization failed\n");
                    }
                } else {
                    EbrDebugLog("Class %s not found\n", pClassName);
                }

                [self->_plistStack removeLastObject];

                indentCount --;
            } else if([plist isKindOfClass:[NSNumber class]])
            {
                result = plist;
                [self->_uidToObject setObject:result forKey:uid];
            } else if ([plist isKindOfClass:[NSData class]])
            {
                result=plist;
                [self->_uidToObject setObject:result forKey:uid];
            } else if ([plist isKindOfClass:[NSDate class]]) 
            {
                result=plist;
                [self->_uidToObject setObject:result forKey:uid];
            } else {
                EbrDebugLog("plist of class %s\n", object_getClassName(plist));
                assert(0);
            }
        } else 
        {
            //EbrDebugLog("Found existing item uid=%d\n", uidIntValue);
        }

        return result;
    }

    -(id) decodeRootObject {
        id top = [_propertyList objectForKey:@"$top"];
        id values = [top allValues];

        if ([values count] != 1){
            //NSLog(@"multiple values=%@",values);
            assert(0);
            return nil;
        } else {
            id object = [values objectAtIndex:0];
            id uid = [object objectForKey:@"CF$UID"];

            return decodeObjectForUID(self, uid);
        }   
    }

    static id unarchiveObjectWithData(id data)
    {
        id unarchiver = [NSKeyedUnarchiver alloc];
        [unarchiver initForReadingWithData:data];

        return [unarchiver decodeRootObject];
    }

    static BOOL containsValueForKey(NSKeyedUnarchiver* self, NSString* key) 
    {
        return [[self->_plistStack lastObject] objectForKey:key] != NULL ? TRUE: FALSE;
    }

    static id _decodeObjectWithPropertyList(NSKeyedUnarchiver* self, id plist)
    {
        if ([plist isKindOfClass:[NSString class]] || [plist isKindOfClass:[NSData class]] ) {
            return plist;
        }

        if( [plist isKindOfClass:[NSDictionary class]] )
        {
            id uid = [plist objectForKey:@"CF$UID"];

            return decodeObjectForUID(self, uid);
        } else if([plist isKindOfClass:[NSArray class]])
        {
            id result = [NSMutableArray array];
            DWORD           i,count=[plist count];

            for (i = 0;i < count; i++)
            {
                id sibling = [plist objectAtIndex:i];
                id objValue = _decodeObjectWithPropertyList(self, sibling);

                if ( objValue != nil ) {
                    [result addObject:objValue];
                } else {
                    EbrDebugLog("**** Failed to unarchive object *****\n");
                }
            }

            return result;
        } else if ([plist isKindOfClass:[NSNumber class]])
        {
            return plist;
        }

        EbrDebugLog("Object type: %s\n", object_getClassName(plist));
        assert(0);
        //(NSException raise:@"NSKeyedUnarchiverException" format:@"Unable to decode property list with class %@",(plist class]];
        return nil;
    }

    -(id) decodeObjectForKey:(NSString*)key {
        id result;

        id plist = [[_plistStack lastObject] objectForKey:key];

        if(plist == nil)
            result = nil;
        else
            result = _decodeObjectWithPropertyList(self, plist);

       return result;
    }

    static id _numberForKey(NSKeyedUnarchiver* self, id key)
    {
        id result=[[self->_plistStack lastObject] objectForKey:key];

        if(result==nil || [result isKindOfClass:[NSNumber class]])
            return result;

        assert(0);
        //[NSException raise:@"NSKeyedUnarchiverException" format:@"Expecting number, got %@",result];
        return nil;
    }

    static id _valueForKey(NSKeyedUnarchiver* self,id key)
    {
        id result=[[self->_plistStack lastObject] objectForKey:key];

        if(result==nil || [result isKindOfClass:[NSValue class]])
            return result;

        assert(0);
        //[NSException raise:@"NSKeyedUnarchiverException" format:@"Expecting number, got %@",result];
        return nil;
    }

    -(BOOL) containsValueForKey:(NSString*)key {
        return ([[_plistStack lastObject] objectForKey:key]!=nil) ? TRUE : FALSE;
    }

    -(id) decodeObject {
        NSString* idNum = [NSString stringWithFormat:@"$%d", _curUid++];
        return [self decodeObjectForKey:idNum];
    }
        
    -(int) decodeIntForKey:(NSString*)key {
       id number = _numberForKey(self, key);

       if ( number == nil ) return 0;

       return [number intValue];
    }

    -(int) decodeInt32ForKey:(NSString*)key {
        return [self decodeIntForKey:key];
    }

    -(int) decodeIntegerForKey:(NSString*)key {
        return [self decodeIntForKey:key];
    }

    -(BOOL) decodeBoolForKey:(NSString*)key {
        return [self decodeIntForKey:key];
    }

    -(__int64) decodeInt64ForKey:(NSString*)key {
       id number=_numberForKey(self, key);

       if(number==nil)
        return 0;

       unsigned __int64 val;

       [number _copyInt64Value:&val];

       return val;
    }

    -(float) decodeFloatForKey:(id)key {
       id number=_numberForKey(self, key);

       if(number==nil)
        return 0;

       float ret = [number floatValue];

       return ret;
    }

    -(double) decodeDoubleForKey:(id)key {
       id number=_numberForKey(self, key);

       if(number==nil)
        return 0;

       double ret = [number doubleValue];

       return ret;
    }

    -(CGPoint) decodeCGPointForKey:(id)key {
        CGPoint ret = { 0, 0 };
        id value = _valueForKey(self, key);

        if (value != nil) {
            ret = [value CGPointValue];
        }

       return ret;
    }

    +(id) unarchiveObjectWithFile:(NSString*)file {
        id data = [NSData dataWithContentsOfFile:file];

        if ( [data length] == 0 ) return nil;

        NSKeyedUnarchiver* unarchiver = [NSKeyedUnarchiver alloc];
        [unarchiver initForReadingWithData:data];

        id ret = [unarchiver decodeRootObject];
        [unarchiver autorelease];

        return ret;
    }

    +(id) unarchiveObjectWithData:(NSData*)data {
        if ( [data length] == 0 ) return nil;

        NSKeyedUnarchiver* unarchiver = [NSKeyedUnarchiver alloc];
        [unarchiver initForReadingWithData:data];

        id ret = [unarchiver decodeRootObject];
        [unarchiver autorelease];

        return ret;
    }

    -(const uint8_t*) decodeBytesForKey:(NSString*)key returnedLength:(NSUInteger *)length {
        *length = 0;

        id data = [self decodeObjectForKey:key];
        if ( data != nil ) {
            [_dataObjects addObject:data];
            *length = [data length];
            return (const uint8_t *) [data bytes];
        } else {
            return 0;
        }
    }

    -(void) finishDecoding {
    }

    -(BOOL) allowsKeyedCoding {
        return TRUE;
    }

    -(void) _setBundle:(id)bundle {
        _bundle = bundle;
    }

    -(NSBundle*) _bundle {
        return _bundle;
    }

    -(void) dealloc {
        _nameToReplacementClass = nil;
        _propertyList = nil;
        _objects = nil;
        _plistStack = nil;
        _uidToObject = nil;
        _dataObjects = nil;
        _bundle = nil;

        [super dealloc];
    }

    
@end

