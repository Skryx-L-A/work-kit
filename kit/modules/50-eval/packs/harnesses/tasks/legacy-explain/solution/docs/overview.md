# PAYROLL overview

## Purpose

Computes the weekly gross pay of every employee and writes one report line per employee.

## Inputs

`EMPLOYEES.DAT` (EMPLOYEE-FILE): employee id, name, hours worked, hourly rate.

## Outputs

`PAYROLL.RPT` (PAYROLL-REPORT): id, name and gross pay per employee.

## Business rules

- Up to 40 hours are paid at the hourly rate.
- Hours above 40 are overtime and paid at 1.5 times the hourly rate.
