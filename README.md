# Changelog

## [1.1.0] - 2026-04-08

### Added

* ox_target in so ores don’t just sit on the ground anymore, you can third-eye them now
* `client/collection.lua` — handles all that spawning + picking up stuff, nothing fancy
* server keeps track of ores now (`CollectableOres`) so people don’t try dumb shit and exploit it (I cried at this)
* made it so only the person who mined it can see it (no stealing like lil rats)
* if you reconnect it just gives your ores back
* ores clean themselves up after like 5 mins if you can’t be bothered picking them up
* if you leave, your stuff gets wiped (obviously)
* added `ox_target` (pretty sure you use it) as dependency so yeah, don’t forget that or it’ll break

### Changed

* `server/server.lua` — stopped using that old drop system and now just triggers `prp-mining:spawnCollectible`
* `fxmanifest.lua` — added collection file to escrow ignore and sorted dependencies properly

### UI Branding (external stuff)

* `esx_progressbar` — made it baby blue (#89CFF0), as blue as could be (Colour blind)
* `esx_textui` — same thing, blue borders
* changed the `~b~` colour to match as well so it’s not all over the place
* Did this completely fucking blind, so below is what it might look like idk fuck know.
* **Did not want to crack .fxap without your consent**

### Removed

* removed that ugly ground drop system, was shit anyway
* removed `dd-mining` resource since it’s all merged now
