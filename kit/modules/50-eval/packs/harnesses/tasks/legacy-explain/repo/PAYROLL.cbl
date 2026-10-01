       IDENTIFICATION DIVISION.
       PROGRAM-ID. PAYROLL.
      * Weekly gross pay per employee. Synthetic example for evaluations.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT EMPLOYEE-FILE ASSIGN TO "EMPLOYEES.DAT".
           SELECT PAYROLL-REPORT ASSIGN TO "PAYROLL.RPT".
       DATA DIVISION.
       FILE SECTION.
       FD  EMPLOYEE-FILE.
       01  EMP-RECORD.
           05 EMP-ID          PIC 9(5).
           05 EMP-NAME        PIC X(20).
           05 EMP-HOURS       PIC 9(3)V9.
           05 EMP-RATE        PIC 9(3)V99.
       FD  PAYROLL-REPORT.
       01  REPORT-LINE        PIC X(60).
       WORKING-STORAGE SECTION.
       01  WS-EOF             PIC X VALUE "N".
       01  WS-REGULAR         PIC 9(5)V99.
       01  WS-OVERTIME        PIC 9(5)V99.
       01  WS-GROSS           PIC 9(6)V99.
       01  WS-OUT.
           05 OUT-ID          PIC 9(5).
           05 FILLER          PIC X VALUE SPACE.
           05 OUT-NAME        PIC X(20).
           05 FILLER          PIC X VALUE SPACE.
           05 OUT-GROSS       PIC ZZZ,ZZ9.99.
       PROCEDURE DIVISION.
       MAIN-PARA.
           OPEN INPUT EMPLOYEE-FILE OUTPUT PAYROLL-REPORT
           PERFORM UNTIL WS-EOF = "Y"
               READ EMPLOYEE-FILE
                   AT END MOVE "Y" TO WS-EOF
                   NOT AT END PERFORM CALC-PAY
               END-READ
           END-PERFORM
           CLOSE EMPLOYEE-FILE PAYROLL-REPORT
           STOP RUN.
       CALC-PAY.
           IF EMP-HOURS > 40
               COMPUTE WS-REGULAR = 40 * EMP-RATE
               COMPUTE WS-OVERTIME = (EMP-HOURS - 40) * EMP-RATE * 1.5
           ELSE
               COMPUTE WS-REGULAR = EMP-HOURS * EMP-RATE
               MOVE 0 TO WS-OVERTIME
           END-IF
           COMPUTE WS-GROSS = WS-REGULAR + WS-OVERTIME
           MOVE EMP-ID TO OUT-ID
           MOVE EMP-NAME TO OUT-NAME
           MOVE WS-GROSS TO OUT-GROSS
           WRITE REPORT-LINE FROM WS-OUT.
