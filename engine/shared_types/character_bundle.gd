class_name CharacterBundle
extends RefCounted

## CharacterBundle — aggregated character state loaded from the database.
##
## Pure data container. Populated by character_sheet_overlay._load_character()
## and passed to each tab's display() method.

var character: CharacterData = null
var proficiencies: Array = []     ## Array[Dictionary] from character_proficiencies table
var inventory: Array = []         ## Array[Dictionary] from inventory_items table
var spells: Array = []            ## Array[Dictionary] from character_spells table (active repertoire)
var formulas: Array = []          ## Array[Dictionary] from character_spell_formulas (arcane only)
var expended_slots: Dictionary = {}  ## spell_level(int) -> expended_count(int) for today
var powers: Array = []            ## Array[Dictionary] from character_powers table
var conditions: Array = []        ## Array[Dictionary] from character_conditions table
var active_effects: Array = []    ## Array[Dictionary] from active_effects table
var henchmen: Array = []          ## Array[Dictionary] from characters table (employer_id match)
