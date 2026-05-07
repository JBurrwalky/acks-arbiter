# GDD: setting lore

**Document type:** Game Design Document (project-designed, modifiable)
**Status:** Rough Draft
**Version:** v0.1
**Depends on:** 
**Replaces:** 
**Blocks:** gdd-setting-generation

# 1. Document Purpose

## 1.1 Scope

This document will:
- outline the shared setting lore that will pre-populate all setting generation sessions at runtime and will inform setting generation decisions.
- contain basic information on setting history, metaphysics, 
- list and overview available cultures for populating a setting, 
- provide alignment definitions for Lawful, Neutral, Chaotic, 
- outline various foundational pantheons of gods and religious doctrines for setting generation to modify per-culture (with non-binding illustrative examples)

It will NOT be an exhaustive description of any specific cultures, it will not dicate a specific map or climate type, it will not dictate setting history beyond the deep history of the setting, it will not dictate the existence of any specific in-game NPCs. It will not dictate the dominant religion of any culture, or the culture-specific variations on the underlying religions.

## 1.2 Rationale

This document and the setting info it contains exist to:
- Provide an internally consistent basic infrastructure for further procedural generation of campaign-specific lore
- Lighten the computational load of the LLMs tasked with setting and lore creation
- Reduce the risk of internally inconsistent drift during LLM setting lore generation
- Provide a bounded framework for world histories and available cultures to ensure that campaign-specific culture selections and histories match available graphical assets, character classes, items, and monster catalogs.
- Create an Arbiter-specific setting brand that, while nearly infinitely variable per-campaign, has a stable and consistent deep lore underlayer.
- Create a credible claim to IP for legal and licensing purposes.

## 1.3 Format and Contents

This document will contain the following sections:
- 2 Metaphysics
- 2.1 Alignment definitions
- 2.2 Magic power and Divine power rationales (narrative explanation of game mechanincs ONLY, does not affect actual game mechanics in any way).
- 2.3 General Cosmology
- 3 History
- 3.1 Scope definitions - what is pre-defined, what is campaign-specific
- 3.2 Creation of the world
- 3.3 Pre-history and the rise of evil
- 3.4 Cataclysmic event options
- 4 Religions
- 4.1 Underlying Entities
- 4.2 Alignment-Specific variations
- 4.3 Cultural Variations
- 4.4 Major Departures/New Religions
- 5 Cultures
- 5.1 Real-world analog sources
- 5.2 Canonical Culture List
- 5.3 Culture specific rules
- 6 Setting Generation application

# 2 Metaphysics

## 2.1 Alignment Definitions

This section will define Lawful, Chaotic, and Neutral alignments, both in their cosmological/metaphysical levels and how they apply concretely to individual behavior, as well as strict rules for what they are NOT.

### 2.1.1 What alignment is NOT

Contrary to most modern RPG conventions, alignment in ACKS, and therefore in Arbiter, is not:
- Personality or temperament
- Multi-axis Law-Chaos X Good-Evil
- Fixed per character forever
- merely a meta-game abstraction unknown to the in-universe characters

### 2.1.2 What Alignment IS

In ACKS, and therefore in Arbiter:
- Alignment is both a metaphysical, cosmological reality and a governing personal philosophy or ethic
- Alignment is both descriptive of a person's ethical and moral trajectory, and prescriptive for continued adherence to the Alignment
- Known in-universe to characters
- An allegiance (knowing or unknowing) to a specific cosmological faction and eschatalogical goal
- Tied intrinsically to in-world religions

### 2.1.3 Law/Lawful

#### 2.1.3a What Lawful alignment IS

The Law/Lawful Alignment is the philosophy and ethic of the gods of law, order, justice, mercy, and collective wellbeing. It is strongly associated with concepts of light, justice, healing, nobility, and magnanimity.

The goal of the alignment of Law is a well-ordered, harmonious world in which everyone from the lowliest peasant to the highest lord, and gods too, has their place and knows it, and both gives and receives what is owed when it is owed to whom it is owed, but where mercy and leniency are observed alongside justice.

Law favors the Light because light allows clarity and clarity allows the right ordering of things and the right judging of deeds. It does not abhor the dark, but will use the dark to confound Chaos and evildoers.

Law abhors senseless cruelty and petty extortion, but does not prohibit slave labor, harsh taxation,violence or even torture to serve a lawful end, provided the needs outweigh the cost: a lawful ruler may overtax the peasants in wartime to prevent defeat, but a ruler who does so for his own hedonism has lapsed from the path of Law. Law condemns murder, theft, rape, fraud, blackmail, unjustified warfare against other lawful or non-hostile neutral nations (war against chaos is always a just cause).

Law favors justice, mercy, honesty, fair dealing, honor, piety, and duty.

Law favors mercy wherever it can be granted without harm to justice: a debtor who is impoverished through no negligence of his own ought to be granted some celmency in repayment, a peasant who is injured ought be healed before being returned to work. But a debtor who gambles away his money rather than repay a debt deserves indentured servitude or garnishment to pay back what he owes, and a wilful criminal ought never be granted clemency.

Law favors the rule of Law, whether by Code, Decree, or merely custom: every man held to the standards of society whatever those might be, but it does not require that all men be equal before the law. Nevertheless, no man is above it, and the Law is something deeper than mere whim of the sovereign; specific laws and customs ought to be expressions of the deeper metaphysical realities of order, harmony, and justice.

A person who is Law aligned is one who, generally, prefers the world to be in right order and harmony, respects legitimate established hierarchy (when not tyrannical or chaotic itself), honors ancestral customs, civic duties, familial bonds and honor; refuses or is hesitant to benefit self at the expense of the community; honors the gods as a matter of justice not just for personal blessing and gain; does not wince at justice being carried out; a lawful character regards the forces of Chaos as metaphysical threats, at least conceptually, and finds Chaotic acts and persons morally repugnant if discovered.

#### 2.1.3b What Lawful Alignment is NOT

Lawful alignment is NOT real-world Christianity, Buddhism, Socialism, Capitalism, or any other real world religion or philosophy with the serial number filed off.

Lawful alignment is NOT egalitarian. Lawful alignment is NOT pacifist. Lawful alignment is not goody-two-shoes. It is not prim-and-proper.

Lawful alignment is not an OCD personality template. Lawful alignment is not a blind zealotry. Lawful alignment is not inherently sneering and proud, nor inherently meek and humble.

A lawful aligned character is not inherently good, and may well extract all he can from others within the most-strained understanding of the law that he can. A lawful aligned character may be a slaver, a loan-shark, a pimp, a mercenary, or he may be a liberator, an alms-giver, an advocate, a peacemaker; so long as it all comports with the customs and laws of his culture and that culture's laws and customs, and does not knowingly serve the gods Chaos, or knowingly offend or hinder the gods of Law.

#### 2.1.3c The Metaphysics of Law

In the Arbiter setting, Law is the governing principle by which the universe, the world, and all that is in it operates in a continuous cycle: every piece has its right place, its right function, its right order. Not everything is equal, there are greater parts and lesser parts, and all are necessary for the continued cycles of the universe. When God made the universe he ordered is such that it would be a continuous, unending cycle of harmonious, even rhythms. Every part would render what was owed to every other part, and all would be content with their place. That original state has been lost, and in its place are now cycles of boom and bust, growth and decay, birth and death, and all things grind slowly toward corruption and stagnation.

God created intermediary gods to administer the original cycles in ways incomprehensible to mortal minds. These gods are now the chief gods worshipped by mortals in the game world. Those that remain faithful to God's original purpose are gods of Law, and they and their followers strive (with varying amounts of zeal), to maintain as much of the harmony of the original state of the world.

The more a mortal aligns with the purposes and strictures of the gods of law, the more he contributes to continuing and maintaining the cycles, and the more his own spiritual power grows as a result of being more perfectly aligned with the metaphysical harmonies underlying the universe. If sufficiently dedicated, his soul, upon death, will ascend to the same planes of exisitence as the gods themselves, and will continue to aid in their work free of the suffering of the world. Some may even become akin to lesser gods themselves. (THis is the in-world explanation of how characters grow in power as they gain levels.)

### 2.1.4 Chaos/Chaotic

#### 2.2.4a What Chaotic Alignment IS

At its root, chaos is the ultimate expression of the notion of the "Will to Power" and might-makes-right. Chaos says: "The strong take what they will, and the weak suffer, and that is the way of things, anyone who says otherwise is a deceiver seeking their own power at your expense." Chaos is the philsophy of pure selfishness: whatever one desires one should seek to obtain at any cost to others.

Chaos is the opposite of law. It is the governing philosophy and ethic of the gods of chaos, tyranny, hedonism, domination, deceit, death, and decay. The governing principle is to accumulate as much to oneself as possible. The chaos gods (truly demons) themselves are locked in constant cosmic power struggles with one another over who gets the lion's share of available power and resources, sometimes even consuming one another when they get the chance. Chaos never has true alliances or friendships, only tenuous parterships for a shared goal rife with risk of betrayal, and the deeper one goes the more lonely it becomes.

It is the rule of undoing, of solve et coagula, disolving the order and harmony of Law so that the individual parts of the cosmic order may be absorbed and consumed, granting greater power to the one doing the consuming. In mortal terms, this means that Chaos often seeks to topple empires only so that a devotee of Chaos may create his own despotic rule on top of the ashes. Such dominions are extractive and oppressive, those who serve have as much taken from them as they take from others. While a Chaotic emperor may be generous to those who serve well, enticing them to further service, but he never knowingly allows them to become threats to his own power and is ever watchful for betrayal

Chaos is dishonest about its own ends, and many who fall into its embrace are self-deluded, believing they serve a cause of freedom and license, or pursue a path of hedonism for its own sake, but it is a freedom that enslaves one to vices or to literal pacts with demons. Chaos corrupts the one who partakes of it, and blinds them to the extent of their own evil, and slowly dulls them to the sufferings of others.

Chaotic beings, being contentious, come in two broad types: the dominating and the pandering. The first seek power or wealth or status and believe themselves capable of obtaining it by their own strength. The second know they are incapable of contending with their betters and seek to avoid destruction while waiting for an opportunity to gain more power or wealth or status for themselves so they may finally become the one who rules. The same person may be both types in different settings: a cruel and vicious taskmaster who abuses slaves and underlings may grovel and bootlick and simper before his own lord or master.

Chaotic gods delight in seeing law destroyed, and in seeing their devotees gain power, for they know that when such devotees die, the chaos god to whom they most closely aligned will get to consume their soul and obtain the power of the devotee entirely, and it deprives the gods of law of an agent. The gods of chaos, and their followers, reward cruelty, dominance, exploitation, extortion, fraud, hatred, excessive punishment for slights, unchecked aggression and conquest, sexual depravity, and all forms of destructive or self-destructive behavior.

Chaos views all virtuous deeds and attitudes as mere means to the end of greater power and corruption, but views the virtues of law to be weaknesses or constraints.

It is worth noting that not ALL chaotic mortals are aware of the depth of the lore of chaos, and many are not so ambitious or power hungry as their gods are, but rather most minions of chaos are merely base hedonists or ne'er-do-wells seeking divine patrons who will aid them in doing what the gods of law forbid and punish. These types are seen by the masters of chaotic lore as useful dupes and as pigs being fattened before being slaughtered.

#### 2.1.4b What Chaotic Alignment IS NOT

Chaos is not mere anarchism, and it is not nihilism. It is not a happy-go-lucky, erratic or flighty personality type. Its adherents are often insane or psychopathic, but that is not a rule. Chaotic alignment does not mean disagreeable or lone-wolf, many of the mightiest chaotic rulers are seducers and enticers.

#### 2.1.4c Metaphysics of Chaos

The origins of the gods of Chaos are shrouded in mystery, and it is a mystery they do not reveal to their devotees. Whether there was ever a first God of chaos or if it has always been a pantheon is unknown. Similarly it is unknown whether the gods of chaos always existed as the first God of law has, or if they came into being later, or are corrupted servants of Law. Sages and philosophers argue over such points endlessly.

What is known is that the Choas gods and their followers believe that, in the end, all of reality will be consumed and unified into one being, and it will be the one who consumes all else that remains, while the rest will be gone. Each devotee of chaos strives to accumulate as much spiritual power as possible either to be the Final One Who Remains, or at least to hold on to their individual existence as long as they can.

The doctrines of Chaos universally regard the teachings of Law as deception practiced by the gods of Law who seek only to weaken their followers so they may consume them when they die, and to prevent any of them from gaining sufficient power in life to cheat death or to ascend to godhood and avoid being consumed. Whether the Choas Gods know this is false or not is unknown.

While each individual chaotic entity seeks to accumulate as much power to itself as it can, neither the gods of chaos nor the mortal devotees of chaos are stupid: they know that they cannot fight each other and the forces of law at the same time. As such, the gods of chaos tend to align into pantheons that cover a wide range of spiritual domains much the way an adventuring party tries to cover a wide range of skills. These pantheons are temporary alliances, mutual pacts to aid one another and avoid internal conflict until all other threats are dealt with. Chaotic adventuring parties and chaotic kingdoms operate with the same mentality. 

When a chaotic follower of sufficient ambition sets out to gain power, the gods of chaos will sometimes lend their own power to him or her to further their own goals, power they expect to re-absorb when the follower dies. But by committing acts of chaos the chaotic mortal also gains power from those they harm and from the world around them, absorbing the spiritual power of those they dominate, slay, or otherwise harm. (This is another in world justification for the power gain of leveling up).

## 2.2 Magic Power and Divine Power

In Arbiter's setting, Magic Power and Divine Power are both the same energy of creation that enables all things to exist. Lower order things (rocks, plants) possess lesser amounts of it, higher order things possess greater amounts of it (animals, humans, spirits). Some objects contain unusually high amounts of such power in specific configurations, such things are magical ingredients or spell components. Some creatures are more naturally attuned to it, like Elves or certain magical animals or plants, and contain or channel amounts of such energy uncommon for creatures of their kind.

The gods thrive on it, and are in some sense composed entirely of it, as are souls. 