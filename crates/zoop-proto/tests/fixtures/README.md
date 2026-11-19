# Synthetic wire fixtures

These packets are constructed from the documented format-1 offsets, with zeroed
unused fields, fixed timestamps and invented measurements. They contain no strap
capture or user data. The legacy filename remains to avoid breaking test tooling.

They test CRC validation and known/unknown packet dispatch. They are not evidence
of interoperability with hardware; that is verified separately on a paired strap.
