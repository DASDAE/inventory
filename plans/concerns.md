My main concern with spool.attch_inventory is that it will become slow to extract patches. So, I propose the following  (Let's discuss)

1. attach_inventory is lazy; it does nothing until a select doesnt resolve against the index and might need the inventory (then it loads it to see). This allows an inventory to be cheaply attached. We might even encourage (or at least support) keeping an inventory in a blessed name in a spool directory (eg .inventory) for an auto-attach. Merging spools should drop any inentory references (loaded or not)

2. We add a new spool method called "enrich" that does exactly the same as patch.enrich (each patch comming out is now enriched)

3. We add a new spool method called prune_to_inventory(inventory=None) for the prunning that currently happens at attch time. 