# Project folder structure
    \PythonDBProjects/
        ├── QueryPerDbPerInstance/
        │       ├── config/
        |       │     └── instances.txt
        │       ├── logs/
        │       └── output_sql_scripts/
        ├── sql_utils/
        │   ├── __init__.py    # Empty file to indicate this is a package
        │   └── db_utilities.py  # Shared functions
        |── 1_Runqueries.py  # Script to extract FK/TR DDL and Drop/Disable them
        └── 2_ExecuteOutputSQL.py  # Script to Create/Enable FK/TR DDL  

# Step 1
## Execution: Path\PythonDBProjects>python 1_Runqueries.py
It will:
1. Save all the commands to create FKs and enable TRs in the folder .\QueryPerDBPrInstance\output_sql_scripts 
2. Drop all FKs and Disable all TRs
3. Once it finishes, in Notepad++ look for "Error executing" for all the files in the folder \QueryPerDBPrInstance\logs
4. Run manually the commands for these databases:
    a. Go to line 42 and add the where clause with the databases that errored out
    b. Comment the portion of code wich doesn't need to be done manually (# Manage Triggers line 67 to line 75) during the tests, it only Manage ForeingKeys failed for 2 databases
    c. Save the changes
    d. Generate the missing create commands connecting manually to the instance.database
    e. Save the create/enable commands in the folder .\QueryPerDBPrInstance\output_sql_scripts (name the files accoprgind to the ame convention, only for clarification reasons)
    f. Run the Drop/ Disable commands in the target server
    g. Go to line 42 and remove the where clause with the databases that errored out
    h. Uncomment the portioned commented in b
    i. Save the changes

# Step 2
## DMS Tool for Rollback    

# Step 3
## Execution: Path\PythonDBProjects>python 2_ExecuteOutputSQL.py
1. Compress all the log files
2. Execute the python script. It will **create the FKs and TRs** in the target server