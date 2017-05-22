/**
 MIT License
 
 Copyright (c) 2017 Stefan Sullivan
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */


#import "OSCMessage.h"

//global-ish value
const char nullCharacters[4] = {'\0', '\0', '\0', '\0'};

@implementation OSCMessage

@synthesize address, format, data;


//initializers
- (id)init {
    self = [super init];
    if (self) {
        format = @",";
    }
    return self;
}
- (id)initWithAddress:(NSString *)destination {
    self = [self init];
    [self setAddress:destination];
    return self;
}

//setter
- (void)setAddress:(NSString *)newAddress {
    address = [NSString stringWithString:newAddress];
}

//add data to the message (before sending it)
- (void)appendFloat:(float)value {
    //network communication takes place in big endian, so convert from host
    //  endianness to big endian before adding data
    CFSwappedFloat32 networkFloat = CFConvertFloat32HostToSwapped(value);
    
    [self appendStringToFormat:@"f"];
    [self appendData:(void *)&networkFloat length:sizeof(float)];
}
- (void)appendInt:(int)value {
    //network communication takes place in big endian, so convert from host
    //  endianness to big endian before adding data
    value = CFSwapInt32BigToHost(value);
    
    [self appendStringToFormat:@"i"];
    [self appendData:(void *)&value length:sizeof(int)];
}
- (void)appendString:(NSString *)value {
    const char *cString = [value cStringUsingEncoding:NSASCIIStringEncoding];
    
    [self appendStringToFormat:@"s"];
    [self appendData:(void *)cString length:[value length]];
}
- (void)appendBlob:(NSData *)value {
    [self appendStringToFormat:@"b"];
    [self appendData:(void *)[value bytes] length:[value length]];
}

//append data: private helper functions
- (void)appendStringToFormat:(NSString *)formatString {
    format = [format stringByAppendingFormat:@"%@",formatString];
}
- (void)appendData:(void *)dataPointer length:(int)numBytes {
    if(data == NULL)
        data = [NSMutableData dataWithBytes:dataPointer length:numBytes];
    else
        [data appendBytes:dataPointer length:numBytes];
    
    if(numBytes % 4 != 0)
        [data appendBytes:(void *)nullCharacters length:4 - (numBytes % 4)];
}

//return function
- (NSData *)messageData {
    NSMutableData *message;
    
    //we must send some format string, so if nothing else just append 1.0f
    if([format isEqualToString:@","])
        [self appendFloat:1.0];
    
    //Create NSData with address and append 1 to 4 null characters
    message = [NSMutableData dataWithBytes:[address cStringUsingEncoding:NSASCIIStringEncoding]
                                    length:[address length]];
    [message appendBytes:(void *)nullCharacters length:4 - ([address length] % 4)];
    
    //append format string and 1 to 4 null characters
    [message appendBytes:[format cStringUsingEncoding:NSASCIIStringEncoding]
                  length:[format length]];
    [message appendBytes:(void *)nullCharacters length:4 - ([format length] % 4)];
    
    //append data
    [message appendData:data];
    
    //look at the whole message length and append 0 to 3 null characters
    if([message length] % 4 != 0)
        [message appendBytes:(void *)nullCharacters length:4 - ([message length] % 4)];
    
    return message;
}

//static methods to generate message objects
+ (OSCMessage *)messageWithAddress:(NSString *)msgAddress {
    return [[OSCMessage alloc] initWithAddress:msgAddress];
}
+ (OSCMessage *)messageWithAddress:(NSString *)msgAddress floatValue:(float)value {
    OSCMessage *message = [OSCMessage messageWithAddress:msgAddress];
    [message appendFloat:value];
    return message;
}

@end
