# Reaction on rollback

This document describes how one should react on rollbacks.

## Overview

Rollback happens when node's blockchain `A` is not a prefix of another
valid blockchain `B` which has more blocks than `A`. In this case node
will rollback all blocks from `A` which are not in `B` and apply all
blocks from `B` which are not in `A`.  Rollback itself doesn't mean
that the system is broken. It's an integral part of many, if not all,
cryptocurrencies. However, if all stakeholders are honest, always
online, don't have bugs and there are no delays (e. g. networking),
rollbacks are impossible.  In real world only the first condition is
satisfied in Byron (all stakeholders are indeed honest). And it
significantly decreases chances of rollback, but not fully.

Examples:
1. Node `N` creates a block `B` and is immediately stopped before it
   announces it to other nodes. After the node is started again, other
   nodes will create more blocks and `N` will have to rollback `B`.
2. Another example: there is a huge delay in blocks propagation
   (unstable network) and because of that some node may not receive
   block for slot `i` before it ends. And then create block for slot
   `i + 1` (not based on `i`). It will also lead to rollback.

## How to notice rollback

There are several ways to notice that rollback occurred:
1. Messages like these:
  * > Blocks to rollback [62955975]
  * > Blocks have been rolled back: [62955975]
  * > Trying to apply blocks w/ rollback:
2. When rollback happens, node reports it to reporting server. If
   rollback is deep (determined by a constant from configuration),
   misbehaviour is classified as critical.
3. In CSL-2014 we want to add EKG metrics for each misbehaviour, in
   particular for rollbacks.

## How to classify rollback

The most important value is the depth of rollback, i. e. how many
blocks are rolled back. `Blocks to rollback` and `Blocks have been
rolled back` messages contain hashes of blocks, so one can easily
calculate them. Reports sent to reporting server also contain hashes
of blocks. EKG metric (CSL-2014) will contain depth.
