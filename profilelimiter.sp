#include <sourcemod>
#include <regex>
#include "include/system2.inc"
#include "include/restorecvars.inc"

#pragma semicolon 1
#pragma newdecls required

Database db = null;

ConVar g_cDatabase, g_cTime, g_cToken, g_cMessage;

bool g_bIsSQLite = false;

#define SQL_CreateTable \
"CREATE TABLE IF NOT EXISTS `profilelimiter_whilelist` \
(\
	`auth` varchar(32) %s PRIMARY KEY \
);"

public Plugin myinfo = {
	name = "Profile Limiter",
	author = "Xc_ace",
	description = "",
	version = "1.0",
	url = "https://github.com/Cola-Ace/Profile-Limiter"
}

public void OnPluginStart(){
	g_cDatabase = CreateConVar("sm_profile_limiter_db_name", "storage-local", "Database name");
	g_cTime = CreateConVar("sm_profile_limiter_time", "200", "Limit time");
	g_cToken = CreateConVar("sm_profile_limiter_token", "", "Steam web API key");
	g_cMessage = CreateConVar("sm_profile_limiter_message", "游戏时长未满足要求或资料未公开");
	
	AutoExecConfig(true, "profilelimiter");
	ExecuteAndSaveCvars("sourcemod/profilelimiter.cfg");
	
	char dbname[32], error[256];
	g_cDatabase.GetString(dbname, sizeof(dbname));
	db = SQL_Connect(dbname, true, error, sizeof(error));
	if (db == null){
		SetFailState("Database connect failed. %s", error);
	}
	db.SetCharset("utf8mb4");
	
	char dbtype[2], query[512];
	db.Driver.GetIdentifier(dbtype, sizeof(dbtype));
	g_bIsSQLite = dbtype[0] == 's';
	FormatEx(query, sizeof(query), SQL_CreateTable, g_bIsSQLite ? "":"COLLATE 'utf8mb4_general_ci'");
	
	db.Query(SQL_CheckErrors, query);
}

public void OnClientPostAdminCheck(int client){
	if (!IsPlayer(client)) return;
	char auth[32], query[256];
	GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
	FormatEx(query, sizeof(query), "SELECT * FROM profilelimiter_whilelist WHERE auth='%s'", auth);
	db.Query(SQL_CheckClient, query, client);
}

public void SQL_CheckClient(Database l_db, DBResultSet results, const char[] error, int client){
	if (results.FetchRow()){
		LogMessage("player %N in whilelist", client);
		return;
	}
	CheckTime(client);
}

public void SQL_CheckErrors(Database l_db, DBResultSet results, const char[] error, any data){
	if (!StrEqual(error, "")){
		LogError("Query failed. %s", error);
	}
}

stock void CheckTime(int client)
{
	char auth[32], key[128], url[256];
	GetClientAuthId(client, AuthId_SteamID64, auth, sizeof(auth));
	g_cToken.GetString(key, sizeof(key));
	FormatEx(url, sizeof(url), "http://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/?key=%s&steamid=%s&appids_filter[0]=730", key, auth);
    
	System2HTTPRequest httpRequest = new System2HTTPRequest(HttpResponseCallback, url);
	httpRequest.Any = GetClientUserId(client);
	httpRequest.GET();
}

public int HttpResponseCallback(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method)
{
	int client = GetClientOfUserId(request.Any);

	if (!success || response.StatusCode != 200 || !IsPlayer(client))
	{
		LogError("Request Error, Code:%i", response.StatusCode);
		KickClient(client, "游戏时长请求失败");
		return;
	}

  // 获取body
	char[] content = new char[response.ContentLength + 1];
	response.GetContent(content, response.ContentLength + 1);
	
	char message[512];
	g_cMessage.GetString(message, sizeof(message));
	Regex regex = new Regex("(?<=\"playtime_forever\":).*?(?=,)");
	if (regex.Match(content) > 0)
	{
		char time[128];
		regex.GetSubString(0, time, sizeof(time));
        
		int hour = StringToInt(time) / 60;
		LogMessage("player: %N, time: %d", client, hour);
		
		if (hour < g_cTime.IntValue)
		{
			KickClient(client, message);
		}
	} else {
		KickClient(client, message);
	}
    
	delete request;
}

stock bool IsPlayer(int client){
	return IsValidClient(client) && !IsFakeClient(client);
}

stock bool IsValidClient(int client){
	return 1 <= client <= MaxClients && IsClientConnected(client);
}