# Changelog

## 1.1.0

- **Forever's new zones** are listed under their continents: Riverglades in the Eastern Kingdoms, and Mount Hyjal and Shen'dralas in Kalimdor. Zephras Isle, the Skyborne starting island, has a group of its own after Kalimdor; they had all been under Other.
- **Darkspear Islands** is listed under Battlegrounds, and the Crafting writ quests under Professions.
- **Zones that QuestieDB adds later** go where Questie's quest journal puts them, on their continent or in a group of their own, without waiting for an update to Almanac. This needs Questie turned on as well as QuestieDB.
- **The Drowned City, Krol'dok Stronghold, Alcaz Prison and Blackmaw Hold** are listed under Dungeons with their 49 quests, which QuestieDB has but files under no zone. Each quest goes back to QuestieDB's zone once QuestieDB gives it one.
- **Quests QuestieDB files under no zone** are listed where their quest giver stands, or else where they are turned in, instead of under "Unknown zone"; 59 of them go to Mount Hyjal, for example.
- **City of Dalaran's second area** is part of the City of Dalaran dungeon, and The Shaper's Terrace's quests are listed under Un'Goro Crater, where the game's map puts it.
- **Forever Dungeon Journal's entries that are not quests** (the Mallet of Zul'Farrak's page, a repeatable copy of The Medallion of Faith and the Gnomeregan punch cards) are no longer listed as quests.
- **/almanac probe** says when QuestieDB files a quest under no zone.

## 1.0.1

- **XP for quests below your level** now follows WoW: Forever's rule: full XP up to five levels above the quest, 80% at six, 60% at seven and half from eight on (Classic went down to 10%). Where the game lists a quest's XP for your character, Almanac shows that exact number.
- **Skyborne characters** (High Order and Windshaper) now see their faction's quests. Forever keeps these races at quest bits of their own, which Almanac did not know; thanks to evan-zeller-mesh for the fix.
- **"Other races' quests" for the Horde** now lists the quests of the other Horde races. A number too large to hold exactly had dropped the Orc, Undead, Tauren and Troll from the Horde's races.
- **"Other races' quests"** also lists Skyborne-only quests for the rest of their faction, and a quest's reason now names the Skyborne races, such as "Human, High Order Skyborne only".
- **Races and factions** now come from QuestieDB where it publishes them, so Almanac reads quests the way QuestieDB writes them. This also removes a retail race whose quest bit clashed with the Windshaper Skyborne's.
- **The Hall of Thanes and Ruins of Lordaeron** are listed under Dungeons again now that QuestieDB has their quests; they had moved to Other.
- **/almanac probe** shows a quest's races correctly, where Forever's large race masks printed as -2147483648.

## 1.0.0

- First release.
