// From https://github.com/securing/SimpleXPCApp/

#import "AuditTokenHack.h"

@implementation AuditTokenHack

+ (NSData *)getAuditTokenDataFromNSXPCConnection:(NSXPCConnection *)connection {
    audit_token_t auditToken = connection.auditToken;
    return [NSData dataWithBytes:&auditToken length:sizeof(audit_token_t)];
}

@end
