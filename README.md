# SGPIO-INTERFACE

1. Introduction
SGPIO stands for Serial General Purpose Input Output. It is a serial bus protocol defined in the
SFF-8485 specification and is used in storage systems to communicate between a host controller
(initiator) and a backplane (target) that holds disk drives.
The main purpose of SGPIO is to control LED indicators on drive bays (Activity, Locate, Error) and to
read back drive presence status from the backplane. It uses only four signals making it very simple to
implement in hardware.
