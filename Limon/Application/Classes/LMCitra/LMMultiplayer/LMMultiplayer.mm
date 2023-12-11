//
//  LMMultiplayer.mm
//  Limon
//
//  Created by Jarrod Norwell on 10/24/23.
//

#import "LMMultiplayer.h"

@interface LMMultiplayer () {
    std::shared_ptr<NetworkRoomMember> roomMember;
}
@end

@implementation LMMultiplayer
+(LMMultiplayer *) sharedInstance {
    static LMMultiplayer *sharedInstance = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[LMMultiplayer alloc] init];
    });
    return sharedInstance;
}

-(void) directConnect:(NSString *)nickname ipAddress:(NSString *)ipAddress port:(NSString * _Nullable)port password:(NSString * _Nullable)password
   onError:(void (^)(RoomError))onError onRoomStateChanged:(void (^)(RoomState))onRoomStateChanged {
    roomMember = Network::GetRoomMember().lock();
    roomMember->BindOnError([onError](const Network::RoomMember::Error& error) { onError((RoomError)error); }); // TODO: (antique) add actual alert for errors
    roomMember->BindOnStateChanged([onRoomStateChanged](const Network::RoomMember::State& state) { onRoomStateChanged((RoomState)state); });
    
    NSString *prt = NULL;
    if ([port isEqualToString:@""] || port == NULL)
        prt = @"24872";
    else
        prt = port;
    
    if ([password isEqualToString:@""] || password == NULL)
        roomMember->Join([nickname UTF8String], Service::CFG::GetConsoleIdHash(Core::System::GetInstance()), [ipAddress UTF8String],
                         [[NSNumber numberWithInt:[prt intValue]] unsignedIntValue], 0, Network::NoPreferredMac);
    else
        roomMember->Join([nickname UTF8String], Service::CFG::GetConsoleIdHash(Core::System::GetInstance()), [ipAddress UTF8String],
                         [[NSNumber numberWithInt:[prt intValue]] unsignedIntValue], 0, Network::NoPreferredMac, [password UTF8String]);
    
    _connected = TRUE;
}

-(void) leave {
    roomMember->Leave();
    _connected = FALSE;
}
@end
