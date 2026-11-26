# SetComparer

When you shift-hover an item, SetComparer adds a comparison frame for each of your saved Equipment Manager sets. It also puts buttons on each set in the Equipment Manager to move that set's items between your bags and the bank.

## Slash commands

| Command | What it does |
|---|---|
| `/setcompare` | Opens the options panel (also under **Esc → Options → AddOns → SetComparer**) |
| `/setcompare options` | Same as `/setcompare` (`/setcompare config` works too) |
| `/setcompare toggle` | Turns the set comparison frames on or off without opening the panel |

## Options panel

| Setting | Saved for | Default |
|---|---|---|
| **Show set comparison frames**: extra frames when shift-hovering an item | all characters | on |
| **Show stat changes on set frames**: the "If you replace this item..." stat differences on each set frame | all characters | on |
| **Compact set frames**: only the item name and stat changes on each set frame | all characters | off |
| **Show bank buttons in the Equipment Manager**: chest and bag icons on each set | all characters | on |
| **Sets to compare against**: one checkbox per saved set | this character | all ticked |

New sets you save later start ticked.

## Items in the bank

A set frame for an item you can't reach right now (for example, it's in the bank and the bank is closed) still shows your exact copy, with its enchant and random suffix, once the addon has seen that item. Equipping it, having it in your bags, or opening the bank once is enough. These frames don't show durability, and they say "Binds when picked up" instead of "Soulbound".

Items the addon has never seen show the base item with **(item never seen - base stats shown)**.

## Equipment Manager buttons

Each set row has two icons, just left of the green "equipped" checkmark:

| Icon | What it does |
|---|---|
| Chest | **Put items in bank**: moves the set's items from your bags into the bank |
| Bag | **Take items from bank**: moves the set's items from the bank into your bags |

- Both only work with the bank open. Otherwise you get red **"Bank not open"** error text.
- Hover an icon to see how many of the set's items it would move.