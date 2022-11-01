RingSpawns
================================================================================

A different pilot spawn algorithm for Northstar.
Currently playable on at least Pilots vs. Pilots, FFA modes and Attrition.

Name
--------------------------------------------------------------------------------

It's called _RingSpawns_ because you spawn near your most recently spawned
teammate, and the next teammate who dies spawns near you, and so on.

Goals
--------------------------------------------------------------------------------

 1. Not spawning so close to enemies you die instantly
 2. Not spawning so far from enemies you have to run across the map
 3. Not playing in the same area of the map for the whole match
 4. Making big maps fun to play even with just a few players

How the goals are achieved
--------------------------------------------------------------------------------

### Not spawning close to enemies

There is a minimum distance of 25 meters to an enemy pilot at spawn,
which should avoid very close spawns most of the time.
There are also separate settings for enemy titans and spectres.

### Not spawning far from enemies

You spawn near your _most recently_ spawned teammate, which,
on the average, puts you close to your team where the action is occurring.
If there are no teammates alive or in the game, the algorithm tries to put
you at a 75 meter distance from the median enemy position.

### Not playing in the same area

When spawns depend on other players' positions and every player spawns near
their previously spawned teammate, the fights tend to slowly shift around the
map in interesting ways, sometimes occurring in non-standard locations like
the backyard area on Exoplanet, or the dock area on Angel City.

### Making big maps fun with few players

Since spawns depend on your teammates, you spawn close to your friends, and
same for the enemies. This means 2v2 or 3v3 on a big map like Angel City
can still be entertaining, where both teams fight in a smaller area of the map.
The minimap "spawn zone" indicator also adjusts to the median team location at
every death and respawn, which means it's easier to find your enemies.

Caveats
--------------------------------------------------------------------------------

 * This affects pilot spawns only, titans are unaffected
 * TF2 and Northstar add some randomization to spawns, so it's hard to write a very accurate algorithm
 * Some players don't like the lack of 1v1s, maybe this will be solved later

Monitoring
--------------------------------------------------------------------------------

Northstar log spews out `found no valid spawns! spawns may be subpar!` if there
are no valid spawns available. This can happen if:

 1. The minimum enemy distances are too high
 2. There's too many players for the map and/or gamemode
 3. Playing on Colony, spawns there are not great for whatever reason
 4. Combination of 1, 2 and 3

Also set the convar `ringspawns_debug_enabled` to `1` if you want to study
distances at every spawn.

Convars
--------------------------------------------------------------------------------

See [mod.json](./mod.json) for what to tune and why.
