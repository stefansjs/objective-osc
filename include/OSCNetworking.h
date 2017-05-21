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

#import <Foundation/Foundation.h>
#import <CFNetwork/CFNetwork.h>

@protocol OSCNetworkDelegateProtocol <NSObject>

- (void)dispatchOSCMessage:(NSString *)OSCAddress
                 withArray:(NSArray *)OSCData
                    format:(NSString *)OSCFormat;

@end



@interface OSCNetworking : NSObject {
    CFSocketRef SendSocket, ReceiveSocket;
    CFRunLoopSourceRef receiveSource;
    CFDataRef ReceiveAddress;//address from which to receive
    CFDataRef SendAddress;//address to which to send messages
    
    NSObject <OSCNetworkDelegateProtocol> *delegate;
    
    bool connected;
}

@property (nonatomic)           bool sendToPD;
@property (nonatomic, readonly) bool connected;
@property (nonatomic, retain)   NSObject <OSCNetworkDelegateProtocol> *delegate;

//initiate the connection
- (void)openNetworkConnection;
- (void)openNetworkConnectionWithPort:(int)port;

//suspend/resume the connection
- (void)enableListening;
- (void)suspendListening;

//modify the connection
    //packet listening
- (void)setListeningPort:(int)port;
    //packet sending
- (void)setSendingIP:(NSString *)IPAddress;
- (void)setSendingPort:(int)port;

- (NSString *)sendingIP;
- (NSArray *)sendingPorts;
- (int)listeningPort;

//send method
- (CFSocketError)sendUDPPacketWithData:(NSData *)data;

@end
