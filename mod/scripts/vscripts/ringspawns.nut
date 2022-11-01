global function RingSpawns_Init

// approx. 1 meter in hammer units
const METER_MULTIPLIER = 52.5

enum eMinimapVisibility {
    NONE = 0,
    TEAM = 1,
    ALL  = 2
}

struct {
    bool enabled
    float friendDist
    float oneVsXDist
    float minEnemyPilotDist
    float minEnemyTitanDist
    float minEnemyReaperDist
    float lfMapDistFactor
    int minimapVisibility

    array<entity> playerRing = []
    table<int, entity> teamMinimapEnts = {}

    bool debugEnabled
} file

void function RingSpawns_Init()
{
    file.enabled = GetConVarBool("ringspawns_enabled")
    file.debugEnabled = GetConVarBool("ringspawns_debug_enabled")

    if (!file.enabled) {
        Log("ringspawns are disabled")
        return
    }

    file.friendDist = GetConVarFloat("ringspawns_friend_dist") * METER_MULTIPLIER
    file.oneVsXDist = GetConVarFloat("ringspawns_1vx_dist") * METER_MULTIPLIER
    file.minEnemyPilotDist = GetConVarFloat("ringspawns_min_enemy_pilot_dist") * METER_MULTIPLIER
    file.minEnemyTitanDist = GetConVarFloat("ringspawns_min_enemy_titan_dist") * METER_MULTIPLIER
    file.minEnemyReaperDist = GetConVarFloat("ringspawns_min_enemy_reaper_dist") * METER_MULTIPLIER
    file.lfMapDistFactor = GetConVarFloat("ringspawns_lf_map_dist_factor")

    file.minimapVisibility = GetConVarInt("ringspawns_minimap_visibility")
    if (file.minimapVisibility > eMinimapVisibility.ALL) {
        Warn("ringspawns_minimap_visibility too large, defaulting to 2")
        file.minimapVisibility = eMinimapVisibility.ALL
    } else if (file.minimapVisibility < eMinimapVisibility.NONE) {
        Warn("ringspawns_minimap_visibility too small, defaulting to 0")
        file.minimapVisibility = eMinimapVisibility.NONE
    }

    // shorter distances on LF maps
    if (IsLFMap()) {
        Debug("[RingSpawns_Init] LF map, using shorter distances with factor " + file.lfMapDistFactor)
        file.friendDist *= file.lfMapDistFactor
        file.oneVsXDist *= file.lfMapDistFactor
        file.minEnemyPilotDist *= file.lfMapDistFactor
        // unnecessary on LF maps but eh, maybe an admin abuser spawns a titan
        file.minEnemyTitanDist *= file.lfMapDistFactor
        file.minEnemyReaperDist *= file.lfMapDistFactor
    }

    AddCallback_OnPlayerRespawned(OnPlayerRespawned)
    AddCallback_OnPlayerKilled(OnPlayerKilled)
    AddCallback_OnClientDisconnected(OnClientDisconnected)

    // spawn funcs
    GameMode_SetPilotSpawnpointsRatingFunc(GameRules_GetGameMode(), RateSpawnpoints)
    AddSpawnpointValidationRule(CheckMinEnemyDist)
    //SetSpawnZoneRatingFunc(DecideSpawnZone) TODO: maybe not needed at the moment

    Log("ringspawns are enabled")
}


void function RateSpawnpoints(int checkClass, array<entity> spawnpoints, int team, entity player)
{
    // most common case spawn in team modes
    array<entity> livingFriends = GetLivingFriendsInRing(team)
    if (livingFriends.len() > 0) {
        entity lastSpawnedFriend = livingFriends[0]
        RateSpawnpointsWithFriend(checkClass, spawnpoints, team, lastSpawnedFriend)
        return
    }

    // 1vX case for FFA, happens in team modes only without living teammates
    array<entity> livingEnemies = GetLivingEnemiesInRing(team)
    if (livingEnemies.len() > 0) {
        RateSpawnpointsWith1vX(checkClass, spawnpoints, team, livingEnemies)
        return
    }

    // random spawn if you're alone
    foreach (entity spawnpoint in spawnpoints) {
        float rating = RandomFloat(1.0)
        spawnpoint.CalculateRating(checkClass, team, rating, rating)
    }
}

void function RateSpawnpointsWithFriend(int checkClass, array<entity> spawnpoints, int team, entity friend)
{
    foreach (entity spawnpoint in spawnpoints) {
        float rating = ScoreLocationsByPreferredDist(spawnpoint.GetOrigin(), friend.GetOrigin(), file.friendDist)
        spawnpoint.CalculateRating(checkClass, team, rating, rating)
    }
}

void function RateSpawnpointsWith1vX(int checkClass, array<entity> spawnpoints, int team, array<entity> enemies)
{
    vector medianEnemyPos = GetMedianOriginOfEntities(enemies)
    foreach (entity spawnpoint in spawnpoints) {
        float rating = ScoreLocationsByPreferredDist(spawnpoint.GetOrigin(), medianEnemyPos, file.oneVsXDist)

        spawnpoint.CalculateRating(checkClass, team, rating, rating)
    }
}

// the closer the distance between a and b is to preferred, the higher the returned score
float function ScoreLocationsByPreferredDist(vector a, vector b, float preferredDist)
{
    float dist = Distance(a, b)
    float diff = fabs(preferredDist - dist)
    float rating = preferredDist - diff
    return rating
}

// enemy distance validator, could probably combine the loops below later
bool function CheckMinEnemyDist(entity spawnpoint, int team)
{
    vector pos = spawnpoint.GetOrigin()

    // enemy pilot check
    array<entity> nearbyPlayers = GetPlayerArrayEx("any", TEAM_ANY, TEAM_ANY, pos, file.minEnemyPilotDist)
    foreach (entity player in nearbyPlayers) {
        if (player.GetTeam() != team) {
            return false
        }
    }

    // enemy titan check
    nearbyPlayers = GetPlayerArrayEx("any", TEAM_ANY, TEAM_ANY, pos, file.minEnemyTitanDist)
    foreach (entity player in nearbyPlayers) {
        if (player.GetTeam() != team && player.IsTitan()) {
            return false
        }
    }

    // enemy reaper check
    array<entity> nearbyReapers = GetNPCArrayEx("npc_super_spectre", TEAM_ANY, TEAM_ANY, pos, file.minEnemyReaperDist)
    foreach (entity reaper in nearbyReapers) {
        if (reaper.GetTeam() != team) {
            return false
        }
    }

    return true
}

// currently this function never gets called and idk why
entity function DecideSpawnZone(array<entity> spawnzones, int team)
{
    Log("[DecideSpawnZone] if you see this message, tell fvnkhead")
    return spawnzones[RandomInt(spawnzones.len())]
}

void function OnPlayerRespawned(entity player)
{
    if (file.debugEnabled) {
        DebugSpawn(player)
    }

    AddPlayerToRing(player)
    UpdateMinimapEnts()
}

void function OnPlayerKilled(entity victim, entity attacker, var damageInfo)
{
    RemovePlayerFromRing(victim)
    UpdateMinimapEnts()
}

void function OnClientDisconnected(entity player)
{
    RemovePlayerFromRing(player)
    UpdateMinimapEnts()
}

void function UpdateMinimapEnts()
{
    if (!IsFFAGame()) {
        UpdateTeamMinimapEnt(TEAM_IMC)
        UpdateTeamMinimapEnt(TEAM_MILITIA)
    } else {
        return // TODO: FFA minimap ent
    }
}

void function UpdateTeamMinimapEnt(int team)
{
    if (file.minimapVisibility <= eMinimapVisibility.NONE) {
        return
    }

    if (team in file.teamMinimapEnts) {
        entity oldEnt = file.teamMinimapEnts[team]
        if (IsValid(oldEnt)) {
            oldEnt.Destroy()
        }
    }

    array<entity> livingPlayers = GetPlayerArrayOfTeam_Alive(team)
    if (livingPlayers.len() == 0) {
        return
    }

    vector medianTeamPos = GetMedianOriginOfEntities(livingPlayers)
    entity newEnt = CreatePropScript($"models/dev/empty_model.mdl", medianTeamPos)
    SetTeam(newEnt, team)

    newEnt.Minimap_SetObjectScale(0.01 * livingPlayers.len())
    newEnt.Minimap_SetAlignUpright(true)
    newEnt.Minimap_SetHeightTracking(true)
    newEnt.Minimap_SetZOrder(MINIMAP_Z_OBJECT)

    if (file.minimapVisibility >= eMinimapVisibility.TEAM) {
        newEnt.Minimap_AlwaysShow(team, null)
    }

    if (file.minimapVisibility >= eMinimapVisibility.ALL) {
        newEnt.Minimap_AlwaysShow(GetOtherTeam(team), null)
    }

    // these are required, so I don't know how to make this work for FFA
    if (team == TEAM_IMC) {
        newEnt.Minimap_SetCustomState(eMinimapObject_prop_script.SPAWNZONE_IMC)
    } else {
        newEnt.Minimap_SetCustomState(eMinimapObject_prop_script.SPAWNZONE_MIL)
    }
		
    newEnt.DisableHibernation()

    file.teamMinimapEnts[team] <- newEnt
}

void function AddPlayerToRing(entity player)
{
    if (file.playerRing.contains(player)) {
        file.playerRing.remove(file.playerRing.find(player))
    }

    file.playerRing.insert(0, player)
}

void function RemovePlayerFromRing(entity player)
{
    if (file.playerRing.contains(player)) {
        file.playerRing.remove(file.playerRing.find(player))
    }
}

array<entity> function GetLivingFriendsInRing(int team)
{
    array<entity> livingFriends = []
    foreach (player in file.playerRing) {
        if (player.GetTeam() == team && IsAlive(player)) {
            livingFriends.append(player)
        }
    }

    return livingFriends
}

array<entity> function GetLivingEnemiesInRing(int team)
{
    array<entity> livingEnemies = []
    foreach (player in file.playerRing ) {
        if (player.GetTeam() != team && IsAlive(player)) {
            livingEnemies.append(player)
        }
    }

    return livingEnemies
}

array<string> LF_MAPS = [
    "mp_lf_stacks",
    "mp_lf_deck",
    "mp_lf_township",
    "mp_lf_uma",
    "mp_lf_traffic",
    "mp_lf_meadow"
]

bool function IsLFMap()
{
    return LF_MAPS.contains(GetMapName())
}

void function DebugSpawn(entity player)
{
    int team = player.GetTeam()
    string playerName = player.GetPlayerName()
    array<entity> livingFriends = GetLivingFriendsInRing(team)
    array<entity> livingEnemies = GetLivingEnemiesInRing(team)
    string msg = format("'%s' spawned randomly because no living friends or enemies", playerName)
    if (livingFriends.len() > 0) {
        entity friend = livingFriends[0]
        string friendName = friend.GetPlayerName()
        float dist = Distance(player.GetOrigin(), friend.GetOrigin()) / METER_MULTIPLIER
        msg = format("'%s' spawned %.0f meters from '%s'", playerName, dist, friendName)
    } else if (livingEnemies.len() > 0) {
        vector medianEnemyPos = GetMedianOriginOfEntities(livingEnemies)
        float dist = Distance(player.GetOrigin(), medianEnemyPos) / METER_MULTIPLIER
        msg = format("'%s' spawned %.0f meters from median enemy position", playerName, dist)
    }

    Debug("[DebugSpawn] " + msg)
}

void function Log(string msg)
{
    print("[ringspawns/log] " + msg)
}

void function Warn(string msg)
{
    print("[ringspawns/warn] " + msg)
}

void function Debug(string msg)
{
    if (file.debugEnabled) {
        print("[ringspawns/debug] " + msg)
    }
}
