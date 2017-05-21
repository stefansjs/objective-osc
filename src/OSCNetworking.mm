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

#import "OSCNetworking.h"

//unix header
#include <arpa/inet.h>

@implementation OSCNetworking

@synthesize connected;
@synthesize delegate;

//Ok, so here's what I understand about UDP connections.  To listen for data from
//another source, the connection must be a server.  To then tell the OS that data
//received on that port should be delivered to this program, you must bind() to
//the incoming port.  To send data, you need not make any such bind.
//Additionally, in order to send data do another destination, the connection must
//be a client.  You may choose to connect() to the address to which you would like
//to send, but this is not necessary.  If you do not connect() to the sender,
//you will simply have to specify the address to which to send packets.  This is
//preferred for us because we sometimes send to multiple receivers (i.e. Player and PD).


// ----------------------------- Startup Methods -------------------------------
- (void)openNetworkConnection {
    [self openNetworkConnectionWithPort:7000];
}
- (void)openNetworkConnectionWithPort:(int)port
{
    //create the receive address
    [self initReceiveAddressWithPort:(int)port];
    //create the listening socket and bind
    [self enableListening];
    
    //what the hell is this?
    signal(SIGPIPE, SIG_IGN);
    
    //create a new CFDataRef with the send address/port
    PlayerAddress = [OSCNetworking addressWithIPAddress:@"172.0.0.1" withPort:port];
    
    //by default, don't send to pd, but set up the address for it anyways.
    sendToPD = false;
    PDAddress = [OSCNetworking newAddressUsingAddress:PlayerAddress withPort:7001];
}

- (void)initReceiveAddressWithPort:(int)port
{
    //initialize the receive address struct
    struct sockaddr_in address;
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = INADDR_ANY;//use inAddress or anyAddress
    
    ReceiveAddress = CFDataCreate(kCFAllocatorDefault,
                                  (unsigned char *)&address,
                                  sizeof(address));
}

- (void)startListening
{
    CFSocketContext context;
    context.version = 0;
    context.info = (__bridge void *)self;
    context.retain = NULL;
    context.release = NULL;
    context.copyDescription = NULL;
    //configure the receive socket
    ReceiveSocket = CFSocketCreate(kCFAllocatorDefault, //default allocator
                                   PF_INET,             //IPv4 (not IPv6)
                                   SOCK_DGRAM,          //Socket Datagram = UDP Packets
                                   IPPROTO_UDP,         //UDP Protocol
                                   kCFSocketDataCallBack,//callback type
                                   readUDPPacket,       //callback function (c function)
                                   &context);
    
    //update connection parameters
    CFOptionFlags options = CFSocketGetSocketFlags(ReceiveSocket);
    options |= kCFSocketCloseOnInvalidate | kCFSocketAutomaticallyReenableDataCallBack;
    CFSocketSetSocketFlags(ReceiveSocket, options);
    
    //For receiving packets we bind (see comments above)
    //      CFSocketSetAddress() is the CFSocket function for bind()
    CFSocketError err = CFSocketSetAddress(ReceiveSocket, ReceiveAddress);//ReceiveAddress is configured during initialization
    [self checkCFSocketError:err];
    
    //set the runloop for data callbacks
    receiveSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, ReceiveSocket, 0);
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    CFRunLoopAddSource(runLoop, receiveSource, kCFRunLoopDefaultMode);
}

// ------------------------------ Helper methods -------------------------------
// helper methods used to create/modify CFDataRef with given address params


//Create a new address with the given IP address string and port
+ (CFDataRef)addressWithIPAddress:(NSString *)IPAddress withPort:(int)port
{
    //new addresses struct
    struct sockaddr_in address;
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = inet_addr([IPAddress UTF8String]);
    
    //create a CFDataRef with the address
    return CFDataCreate(kCFAllocatorDefault, (unsigned char *)&address, (CFIndex)sizeof(address));
}

//modify an existing CFDataRef (like created in addressWithIPAddress: withPort:)
//  and change the port of the new address. Return it as a CFDataRef
+ (CFDataRef)newAddressUsingAddress:(CFDataRef)SenderAddress withPort:(int)newPort
{
    //struct for reading/writing address
    struct sockaddr_in socketAddress;
    
    //used by CFDataGetBytes
    CFRange dataRange;
    dataRange.location = 0;
    dataRange.length = sizeof(struct sockaddr_in);
    
    //get the data out of the struct
    CFDataGetBytes(SenderAddress, dataRange, (unsigned char *)&socketAddress);
    
    socketAddress.sin_port = htons(newPort);
    
    //Generate a new CFDataRef and return it
    return CFDataCreate(kCFAllocatorDefault,
                        (unsigned char *)&socketAddress,
                        (CFIndex)sizeof(socketAddress));
}
//modify an existing CFDataRef (like created in addressWithIPAddress: withPort:)
//  and change the IP address of the new address. Return it as a CFDataRef
+ (CFDataRef)newAddressUsingAddress:(CFDataRef)SenderAddress withIP:(NSString *)newIP
{
    //struct for reading/writing address
    struct sockaddr_in socketAddress;
    
    //used by CFDataGetBytes
    CFRange dataRange;
    dataRange.location = 0;
    dataRange.length = sizeof(struct sockaddr_in);
    
    //get the data out of the struct
    CFDataGetBytes(SenderAddress, dataRange, (unsigned char *)&socketAddress);
    
    //update the IP
    socketAddress.sin_addr.s_addr = inet_addr([newIP UTF8String]);
    
    //Generate a new CFDataRef and return it
    return CFDataCreate(kCFAllocatorDefault,
                        (unsigned char *)&socketAddress,
                        (CFIndex)sizeof(socketAddress));
}


// ----------------------------- Interface Methods -----------------------------

// Interface methods for turning on/off networking.
- (void)enableListening
{
    [self startListening];
}
- (void)suspendListening
{
    //because we set kCFSocketCloseOnInvalidate during init, this is all we need to do:
    CFSocketInvalidate(ReceiveSocket);
}

// ---------------------------- Getters/Setters

//ports
- (int)listeningPort
{
    return [OSCNetworking portFromAddress:ReceiveAddress];
}
- (void)setListeningPort:(int)port
{
    [self suspendListening];
    [self initReceiveAddressWithPort:port];
    [self enableListening];
}

- (int)sendingPort
{
    return [OSCNetworking portFromAddress:SendAddress];
}
- (void)setSendingPort:(int)port
{
    PlayerAddress = [OSCNetworking newAddressUsingAddress:SendAddress withPort:port];
}

//sending IPs
- (NSString *)sendingIP
{
    return [OSCNetworking IPFromAddress:PlayerAddress];
}
- (void)setSendingIP:(NSString *)IPAddress
{
    //note: this method only works because the IP addresses were already initialized
    //  before the first call of this method (i.e. during init of this object)
    SendAddress = [OSCNetworking newAddressUsingAddress:SendAddress withIP:IPAddress];
}

// ----------------------------- Send UDP Message
- (CFSocketError)sendUDPPacketWithData:(NSData *)data
{
    //Initialize the error to no error
    CFSocketError err = kCFSocketSuccess;
    
    err = CFSocketSendData(ReceiveSocket, SendAddress, (__bridge CFDataRef)data, 0);
    if(err == kCFSocketError){
        NSLog(@"Failed to send UDP packet to %@ (%@)", ReceiveSocket, SendAddress);
        return err;
    }
    else if(err == kCFSocketTimeout){
        NSLog(@"Timeout while trying to send UDP packet to Player");
        return err;
    }
    
    return kCFSocketSuccess;
}

// ------------------------------ Helper methods
// helper methods used to get information out of CFDataRef address (used by getters/setters)

+ (int)portFromAddress:(CFDataRef)address
{
    struct sockaddr_in socketAddress;
    
    //used by CFDataGetBytes
    CFRange dataRange;
    dataRange.location = 0;
    dataRange.length = sizeof(struct sockaddr_in);
    
    //get the data out of the struct
    CFDataGetBytes(address, dataRange, (unsigned char *)&socketAddress);
    
    return ntohs(socketAddress.sin_port);
}
+ (NSString *)IPFromAddress:(CFDataRef)address
{
    struct sockaddr_in socketAddress;
    
    //used by CFDataGetBytes
    CFRange dataRange;
    dataRange.location = 0;
    dataRange.length = sizeof(struct sockaddr_in);
    
    //get the data out of the struct
    CFDataGetBytes(address, dataRange, (unsigned char *)&socketAddress);
    char *ipCString = inet_ntoa(socketAddress.sin_addr);
    //Note, this implementation is heavily IPv4 dependent. To make it more tolerant,
    //  use inet_ntop()
    
    //create an objective-c string and return it
    return [NSString stringWithCString:ipCString encoding:NSASCIIStringEncoding];
}

- (void)checkCFSocketError:(CFSocketError)error
{
    //default error case is for connected to be false
    connected |= false;
    
    //if not successful throw an exception
    if(error != kCFSocketSuccess)
    {
        @throw [NSException exceptionWithName: @"CFSockeError",
                                       reason: @"CFSocket method returned an error code",
                                     userInfo:@{@"CFSocketError", error}];
    }
    
    //otherwise, if we didn't throw an exception, tell ourselves that we connected
    connected |= true;
}

// ------------------------------ Read Callback --------------------------------
void readUDPPacket(CFSocketRef s,
                   CFSocketCallBackType callbackType,
                   CFDataRef address,
                   const void *data,
                   void *info)
{
    //for now, don't do anything
    if(callbackType == kCFSocketReadCallBack){
        NSLog(@"Read Callback");
    }
    else if(callbackType == kCFSocketAcceptCallBack){
        NSLog(@"Accept Callback");
    }
    else if(callbackType == kCFSocketDataCallBack){
        //get data out of the callback
        CFDataRef receivedData = (CFDataRef)data;//not sure if CFData or NSData is better to use here
        
        //This callback is a static method, which means it had no access to member data
        //so we pass the self pointer into a CFContext struct during the creation of the socket
        //then we dereference it here, so that we can call member methods
        OSCNetworking *selfPointer = (__bridge OSCNetworking *)info;
        [selfPointer parseOSCPacket:(__bridge NSData *)receivedData];
    }
    else {
        NSLog(@"Unknown callback type from UDP Socket");
    }
}


// --------------------------- OSC Parsing Methods -----------------------------

- (void)parseOSCPacket:(NSData *)packet {
    //this is just a forwarder routine to packet or bundle parsing.
    //the reason this method is here is because a bundle may contain messages OR
    //bundles, so this method allows you to recurse through the bundle(s)
    
    //OSC packets in UDP (unlike TCP) simply contain the message or bundle
    //  therefore, we simply treat a packet just like any other message/bundle.
    
    //step 1: is the bundle the correct length
    if([packet length] % 4 != 0){
        NSLog(@"Packet is not of valid length, shoudl be multiple of 4\nPacket Length: %d",[packet length]);
        return;
    }
    
    //convert the data to a string to check if the packet is a bundle
    NSString *string = [NSString stringWithCString:(const char *)[packet bytes]
                                          encoding:NSASCIIStringEncoding];//OSC requires ASCII
    
    if([string hasPrefix:@"#bundle"]){
        //theoretically all bundle elements should be processesed simultaneously
        //this means that we would update the internal state of the redwoodPlayer
        //before notifying any of the observers of the change.  However, for the
        //moment I'm assuming that there's no need for this, assuming that the
        //sender (i.e. the c player) is only sending a given variable once per
        //bundle. If this assumption is true, thent here's no redundant information
        [self parseOSCBundle:packet];
    }
    else {
        [self parseOSCMessage:packet];
    }
}

//helper method used by parseOSCBundle:
+ (NSRange)advanceRange:(NSRange)range byLength:(int)length
{
    range.location = range.location + range.length;
    range.length   = length;
    
    return range;
}
- (void)parseOSCBundle:(NSData *)bundle
{
    //for specific details on the OSC protocol see: opensoundcontrol.org/spec-1_0
    //future updates may support OSC 1.1, but for now we support 1.0
    
    //a bundle is formatted thusly:
    //  8 bytes: the string "#bundle"
    //  8 bytes: an OSC time tag. We're not using this presently
    //  any number of messages of the following format
    //      4 bytes: an int32 containing the following message length (should be multiple of 4)
    //      remaining bytes (multiple of 4): the packet contents (message OR bundle)
    
    NSRange dataRange;
    int messageLength;
    
    //get the first 8 bytes: should be "#bundle" (without quotation marks)
    dataRange.location = 0;
    dataRange.length = 8;
    
    
    //the next 8 bytes should be an OSC time tag
    //for the moment, we're ignoring time tag information, so we don't actually read it
    dataRange = [OSCNetworking advanceRange:dataRange byLength:8];
    
    //the next 4 bytes should be the length of the following data
    dataRange = [OSCNetworking advanceRange:dataRange byLength:4];
    
    while (dataRange.location < [bundle length])
    {
        //we have to worry about endianness of bytes when dealing with numbers
        //  network communication is done in big endian
        [bundle getBytes:&messageLength range:dataRange];
        messageLength = CFSwapInt32BigToHost(messageLength);
        
        //get the range of the following data
        dataRange = [OSCNetworking advanceRange:dataRange byLength:messageLength];//however long the bundle tells us the message is
        
        //make sure our data range is a valid range (i.e. not too long)
        int remainingBundleBytes = [bundle length] - dataRange.location;
        if(messageLength > 0 && messageLength <= remainingBundleBytes)
            [self parseOSCPacket:[bundle subdataWithRange:dataRange]];//look at the beautiful recursion
        else {
            NSLog(@"Bundle length doesn't seem right\n bundle length: %d, described length: %d",[bundle length], messageLength);
            dataRange.length = remainingBundleBytes;
            [self parseOSCPacket:[bundle subdataWithRange:dataRange]];
        }
        
        //advance to the next message in the bundle
        dataRange = [OSCNetworking advanceRange:dataRange byLength:4];
    }
}
- (void)parseOSCMessage:(NSData *)message
{
    //for specific details on the OSC protocol see: opensoundcontrol.org/spec-1_0
    //future updates may support OSC 1.1, but for now we support 1.0
    
    //OSC Messages have the following format:
    //  OSC Address pattern: a string starting with "/" (without the quotes)
    //  1 to 4 \0 (i.e. "null") characters
    //  OSC Type Tag String: a string starting with "," (without the quotes)
    //  1 to 4 \0 characters
    //  0 or more OSC Arguments: binary representations of data (according to the type tag string)
    
    //if the string really is a multiple of 4 characters, it seems the message will
    //  have 4 null characters.  This is nice because asking for the NSString
    //  from the c string will automatically terminate at the first null character.
    //This assumption may be error prone for other implementations (other than
    //  libOSCPack) if they use 0 instead of 4 null characters
    
    //The first thing we do is get the string from the start of the message.
    //  Since this string is followed by null characters NSString will stop reading
    //  and return the string (without null characters).  This will be the address
    //  string.
    NSString *addressString = [NSString stringWithCString:(const char *)[message bytes]
                                                 encoding:NSASCIIStringEncoding];
    //then we calculate how many null characters will follow the null string
    const int numNullCharacters = 4 - [addressString length] % 4;
    //then we calculate the starting address of the format string and get that string
    //  again, the string will be followed by null characters, so we will get only
    //  the format in the NSString.
    int formatOffset = [addressString length] + numNullCharacters;
    if(formatOffset >= [message length])
        NSLog(@"Problem with Message length... :*");
        //[[redwoodPlayer defaultPlayer] dispatchWithAddress:addressString];//This can probably be deleted, but I'll leave it for now...
    else {
        NSString *formatString = [NSString stringWithCString:(const char *)[message bytes] + formatOffset
                                                    encoding:NSASCIIStringEncoding];
        //compute the number for null characters following the format string
        numNullCharacters = 4 - [formatString length] % 4;
        
        //The location of all of the binary data
        NSRange dataRange;
        dataRange.location = formatOffset + [formatString length] + numNullCharacters;
        dataRange.length = [message length] - dataRange.location;
        
        //error checking
        if(dataRange.length <= 0){
            NSLog(@"Received an OSC packet with a format string but no data");
            return;
        }
        
        //the binary data
        NSData *data = [message subdataWithRange:dataRange];
        
        //break the format string into substrings
        NSArray *formatArray = [formatString componentsSeparatedByString:@","];
        //since the format string starts with a "," the first object will be empty
        //remove the empty object:
        dataRange.location = 1;
        dataRange.length = [formatArray count] - 1;
        formatArray = [formatArray objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:dataRange]];
        //        formatString = [formatString substringWithRange:dataRange]
        
        //dispatch with format array and data
        [self dispatchWithAddress:addressString
                      formatArray:formatArray
                            value:data];
    }
}

// ----------------------- Dispatch Message to delegate ------------------------
- (void)dispatchWithAddress:(NSString *)OSCAddress formatArray:(NSArray *)OSCFormat value:(NSData *)OSCValue
{
    //parse through the format string.  Do some sanity checking based on the receiver
    if([OSCFormat count] == 1){
        [self dispatchWithAddress:OSCAddress
                     formatString:[OSCFormat objectAtIndex:0]
                            value:OSCValue];
    }
    else {
        //for now, ignore this case, because we don't have this format yet
        NSLog(@"OSC Message with multiple data elements received! (this isn't implemented yet)");
    }
}
- (void)dispatchWithAddress:(NSString *)OSCAddress formatString:(NSString *)OSCFormat value:(NSData *)OSCValue
{
    //Most OSC messages that the redwood c player send have only one float.
    //This special case saves us a lot of effort, so first check this case.
    //Afterwards, we'll check for the more general cases.
    if([OSCFormat isEqualToString:@"f"]){
        float value = [OSCNetworking getFloatFromData:OSCValue withStartPosition:0];
        [delegate dispatchOSCMessage:OSCAddress
                           withArray:[NSArray arrayWithObject:[NSNumber numberWithFloat:value]]
                              format:OSCFormat];
    }
    else {
        // ----------------- Parse Data into an Object Array
        //start by creating an array and for each format type reading this out
        //  of the NSData object and into an NSArray.
        int numArguments = [OSCFormat length];
        NSMutableArray *dataObjects = [NSMutableArray arrayWithCapacity:numArguments];
        
        //dataRange is the range of the data to read for each type.
        NSRange dataRange;
        dataRange.location = 0;//start at the beginning
        dataRange.length = 0;//we don't know the length of the data until we know the type of data.
        
        //this is the "range" for comparing each character of the format string
        NSRange charRange;
        charRange.location = 0;//start at the beginning.
        charRange.length = 1;//always comparing only 1 character
        
        //go through each element and add it to the array
        for(int argument = 0; argument < numArguments; argument++){
            charRange.location = argument;
            dataRange.location = dataRange.location + dataRange.length;
            
            if([OSCFormat compare:@"f"
                          options:NSCaseInsensitiveSearch
                            range:charRange] == NSOrderedSame){
                
                //variables to get the data out of the NSData object with correct endianness
                CFSwappedFloat32 bigEndian;
                float value;
                //size of the range (the location is already updated at the beginning of the loop)
                dataRange.length = sizeof(float);//this is really a static 4 bytes because OSC is ...old
                
                //get the data out of the NSData object
                [OSCValue getBytes:&bigEndian range:dataRange];
                //convert it to host endianness
                value = CFConvertFloat32SwappedToHost(bigEndian);
                //and add it to the array
                [dataObjects addObject:[NSNumber numberWithFloat:value]];
            }
            else if([OSCFormat compare:@"s"
                               options:NSCaseInsensitiveSearch
                                 range:charRange] == NSOrderedSame){
                
                int maxNumChars = [OSCValue length] - dataRange.location;
                char *ASCIIString[maxNumChars];
                //byte order doesn't matter for strings because each char is 1 byte.
                
                //get the string by getting all the rest of the data.  Then use
                //NSString functions to conver this to a string.  This only works
                //if the string has one or more null characters behind it.
                dataRange.length = maxNumChars;
                [OSCValue getBytes:ASCIIString range:dataRange];
                NSString *string = [NSString stringWithCString:(const char *)ASCIIString
                                                      encoding:NSASCIIStringEncoding];
                
                //put the string in the data array
                [dataObjects addObject:string];
                
                //then correct the dataRange for the actual number of characters (including null characters)
                dataRange.length = nextMultipleOfFour([string length]);
            }
            else if([OSCFormat compare:@"i"
                               options:NSCaseInsensitiveSearch
                                 range:charRange] == NSOrderedSame){
                //int data
                int value;
                dataRange.length = sizeof(int);
                
                //retreive the value from OSCValue
                [OSCValue getBytes:&value range:dataRange];
                value = CFSwapInt32BigToHost(value);
                
                //add it to the array
                [dataObjects addObject:[NSNumber numberWithInt:value]];
            }
            else {
                NSLog(@"Unknown format: %hu\n",[OSCFormat characterAtIndex:argument]);
            }
        }
        
        //after all that parsing, send it to the dispatch message with an object
        //  array (instead of an NSData object).
        [delegate dispatchOSCMessage:OSCAddress withArray:dataObjects format:OSCFormat];
    }
}

// ------------------------------ Helper Methods -------------------------------

// Getting data out of UDP packets
+ (float)getFloatFromData:(NSData *)data withStartPosition:(int)location
{
    //Network communication is done in big endian.  I belive mac and windows
    //  both use little endian these days, but I'll check for host endianness
    //  here and convert from big endian if necessary.
    float value;
    
    NSRange dataRange;
    dataRange.location = location;
    dataRange.length = sizeof(float);//this is really a static 4 bytes bescause OSC is old.
    
    if(CFByteOrderGetCurrent() == CFByteOrderLittleEndian){
        CFSwappedFloat32 swappedBytes;
        [data getBytes:&swappedBytes range:dataRange];
        value = CFConvertFloat32SwappedToHost(swappedBytes);
    }
    else {
        [data getBytes:&value range:dataRange];
    }
    
    return value;
}
+ (int)getIntFromData:(NSData *)data withStartPosition:(int)location
{
    int value;
    
    NSRange dataRange;
    dataRange.location = location;
    dataRange.length = sizeof(int);//this is really a static 4 bytes bescause OSC is old.
    
    [data getBytes:&value range:dataRange];
    
    return CFSwapInt32BigToHost(value);
}
+(NSString *)getStringFromData:(NSData *)data withStartPosition:(int)location withMaxLength:(int)length
{
    char *ASCIIString[length];
    
    NSRange dataRange;
    dataRange.location = location;
    dataRange.length = length;
    
    [data getBytes:ASCIIString range:dataRange];
    NSString *stringData = [NSString stringWithCString:(const char *)ASCIIString
                                              encoding:NSASCIIStringEncoding];
    
    return stringData;
}

int nextMultipleOfFour(int input)
{
    //    if(input % 4 == 0)
    //        return input;
    //else
    return input + 4 - (input % 4);
}


// Required by Objective-C:
- (void)dealloc {
    CFSocketInvalidate(ReceiveSocket);
}


@end
