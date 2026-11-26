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
| **Show bank buttons in the Equipment Manager**: chest and bag icons on each set | all characters | on |
| **Sets to compare against**: one checkbox per saved set | this character | all ticked |

New sets you save later start ticked.

## Equipment Manager buttons

Each set row has two icons, just left of the green "equipped" checkmark:

| Icon | What it does |
|---|---|
| Chest | **Put items in bank**: moves the set's items from your bags into the bank |
| Bag | **Take items from bank**: moves the set's items from the bank into your bags |

- Both only work with the bank open. Otherwise you get red **"Bank not open"** error text.
- Hover an icon to see how many of the set's items it would move.