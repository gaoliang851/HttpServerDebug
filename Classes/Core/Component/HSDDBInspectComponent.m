//
//  HSDDBInspectComponent.m
//  HttpServerDebug
//
//  Created by chenjun on 2018/4/28.
//  Copyright © 2018年 chenjun. All rights reserved.
//

#import "HSDDBInspectComponent.h"
#import "FMDB.h"
#import "HSDManager+Private.h"
#import "HSDDefine.h"
#import <sqlite3.h>

@implementation HSDDBInspectComponent

+ (NSString *)fetchTableNamesHTMLString:(NSString *)dbPath {
    NSMutableString *selectHtml;
    FMDatabase *database = [FMDatabase databaseWithPath:dbPath];
    if (dbPath.length > 0 && [database open]) {
        // all tables
        selectHtml = [[NSMutableString alloc] init];
        NSString *stat = [NSString stringWithFormat:@"SELECT * FROM sqlite_master WHERE type='table';"];
        FMResultSet *rs = [database executeQuery:stat];
        while ([rs next]) {
            NSString *tblName = [rs stringForColumn:@"tbl_name"];
            tblName = tblName.length > 0? tblName: @"";
            NSString *optionHtml = @"<option value='%@' %@>%@</option>";
            if (selectHtml.length == 0) {
                // default select first table
                optionHtml = [NSString stringWithFormat:optionHtml, tblName, @"selected='selected'", tblName];
            } else {
                optionHtml = [NSString stringWithFormat:optionHtml, tblName, @"", tblName];
            }
            [selectHtml appendString:optionHtml];
        }
        [rs close];
        [database close];
    }
    return [selectHtml copy];
}

+ (NSData *)queryTableData:(NSString *)dbPath tableName:(NSString *)tableName {
    FMDatabase *database = [FMDatabase databaseWithPath:dbPath];
    NSMutableArray *allData = [[NSMutableArray alloc] init];
    if (dbPath.length > 0 && tableName.length > 0 && [database open]) {
        NSMutableArray *record = [[NSMutableArray alloc] init];
        // field names
        NSString *stat = [NSString stringWithFormat:@"PRAGMA TABLE_INFO(%@)", tableName];
        FMResultSet *rs = [database executeQuery:stat];
        while ([rs next]) {
            NSString *fieldName = [rs stringForColumn:@"name"];
            fieldName = fieldName.length > 0? fieldName: @"";
            [record addObject:fieldName];
        }
        [rs close];
        [allData addObject:record];
        
        // query data
        stat = [NSString stringWithFormat:@"SELECT * FROM %@;", tableName];
        rs = [database executeQuery:stat];
        int columnCount = [rs columnCount];
        while ([rs next]) {
            record = [[NSMutableArray alloc] init];
            for (int i = 0; i < columnCount; i++) {
                NSString *tmp = [rs stringForColumnIndex:i];
                tmp = tmp.length > 0? tmp: @"";
                [record addObject:tmp];
            }
            [allData addObject:record];
        }
        [rs close];
        [database close];
    }
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:allData options:0 error:nil];
    return data;
}

+ (NSData *)queryDatabaseSchema:(NSString *)dbPath {
    FMDatabase *database = [FMDatabase databaseWithPath:dbPath];
    NSMutableDictionary *allData = [[NSMutableDictionary alloc] init];
    if (dbPath.length > 0 && [database open]) {
        FMResultSet *rs = [database getSchema];
        
        // entities
        NSMutableArray *tableArr = [[NSMutableArray alloc] init];
        NSMutableArray *indexArr = [[NSMutableArray alloc] init];
        NSMutableArray *viewArr = [[NSMutableArray alloc] init];
        NSMutableArray *triggerArr = [[NSMutableArray alloc] init];
        NSString *tableType = @"table";
        NSString *indexType = @"index";
        NSString *viewType = @"view";
        NSString *triggerType = @"trigger";
        while ([rs next]) {
            NSString *type = [rs stringForColumn:@"type"];
            NSString *name = [rs stringForColumn:@"name"];
            name = name.length > 0? name: @"";
            NSString *tbl_name = [rs stringForColumn:@"tbl_name"];
            tbl_name = tbl_name.length > 0? tbl_name: @"";
            NSString *sql = [rs stringForColumn:@"sql"];
            sql = sql.length > 0? sql: @"";
            NSDictionary *dict =
            @{
              @"name": name,
              @"tbl_name": tbl_name,
              @"sql": sql
              };
            
            if ([type isEqualToString:tableType]) {
                [tableArr addObject:dict];
            } else if ([type isEqualToString:indexType]) {
                [indexArr addObject:dict];
            } else if ([type isEqualToString:viewType]) {
                [viewArr addObject:dict];
            } else if ([type isEqualToString:triggerType]) {
                [triggerArr addObject:dict];
            }
        }
        
        [allData setObject:tableArr forKey:tableType];
        [allData setObject:indexArr forKey:indexType];
        [allData setObject:viewArr forKey:viewType];
        [allData setObject:triggerArr forKey:triggerType];
        
        [rs close];
        [database close];
    }
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:allData options:0 error:nil];
    return data;
}

+ (NSData *)executeSQL:(NSString *)dbPath sql:(NSString *)sqlStr {
    // execute sql
    sqlStr = [sqlStr stringByRemovingPercentEncoding];
    FMDatabase *database = [FMDatabase databaseWithPath:dbPath];
    BOOL res = NO;
    NSString *errMsg = @"";
    NSMutableArray *allData = [[NSMutableArray alloc] init];
    if (dbPath.length > 0 && sqlStr.length > 0 && [database open]) {
        res = [HSDDBInspectComponent executeStatements:sqlStr withFMDB:database withResultBlock:^int(NSDictionary *resultsDictionary) {
            // field names
            NSArray *fields;
            if ([allData count] > 0) {
                fields = [allData firstObject];
            } else {
                fields = [resultsDictionary allKeys];
                [allData addObject:fields];
            }
            // result set
            NSMutableArray *record = [[NSMutableArray alloc] init];
            for (NSString *field in fields) {
                id tmp = [resultsDictionary objectForKey:field];
                NSString *valueStr = @"";
                if ([tmp isKindOfClass:[NSString class]]) {
                    valueStr = (NSString *)tmp;
                }
                [record addObject:valueStr];
            }
            [allData addObject:record];
            return 0;
        }];
        errMsg = database.lastErrorMessage;
        [database close];
    }
    // construct response json
    errMsg = errMsg.length > 0? errMsg: @"";
    NSDictionary *resDict =
    @{
      @"status": @(res),
      @"errMsg": errMsg,
      @"resultSet": allData
      };
    NSData *data = [NSJSONSerialization dataWithJSONObject:resDict options:0 error:nil];
    return data;
}

#pragma mark - FMDB

/**
 *  Original -[FMDatabase executeStatements:withResultBlock:] interface has potential crash bugs.
 *  Reproduction: select records with blob type field
 */
+ (BOOL)executeStatements:(NSString *)sql withFMDB:(FMDatabase *)db withResultBlock:(int(^)(NSDictionary *))block {
    int rc;
    char *errmsg = nil;
    
    rc = sqlite3_exec([db sqliteHandle], [sql UTF8String], block ? HSDFMDBExecuteBulkSQLCallback : nil, (__bridge void *)(block), &errmsg);
    
    if (errmsg && [db logsErrors]) {
        NSLog(@"Error inserting batch: %s", errmsg);
        sqlite3_free(errmsg);
    }
    
    return (rc == SQLITE_OK);
}

int HSDFMDBExecuteBulkSQLCallback(void *theBlockAsVoid, int columns, char **values, char **names) {
    if (!theBlockAsVoid) {
        return SQLITE_OK;
    }
    
    int (^execCallbackBlock)(NSDictionary *resultsDictionary) = (__bridge int (^)(NSDictionary *__strong))(theBlockAsVoid);
    
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)columns];
    
    for (NSInteger i = 0; i < columns; i++) {
        NSString *key = [NSString stringWithUTF8String:names[i]];
        id value = values[i] ? [NSString stringWithUTF8String:values[i]] : [NSNull null];
        // value can be nil (when values[i] is blob type)
        value = value ? value : [NSNull null];
        [dictionary setObject:value forKey:key];
    }
    
    return execCallbackBlock(dictionary);
}

@end
