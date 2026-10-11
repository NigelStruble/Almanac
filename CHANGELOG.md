# Changelog

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
