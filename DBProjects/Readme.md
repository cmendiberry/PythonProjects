# Project folder structure
    \PythonDBProjects/
        ├── AuxQueries/ #For Failed databases when running 3_RunQueries.py
        │      |── FK_ScriptOut.sql
        |      └── TR_ScriptOut.sql
        |── QueryPerDbPerInstance/
        │       ├── config/
        |       │     |── instance.txt
        |       |     └── sourceddl.txt
        │       ├── logs/
        │       └── output_sql_scripts/
        ├── sql_utils/
        │   ├── __init__.py    # Empty file to indicate this is a package
        │   └── db_utilities.py  # Shared functions
        |── 1_CloneSource.py # For all selected databases in the MSSQL instance: clone, backup clone and drop clone
        |── 2_RestoreClones.py  # Restore clone backups under their original name in target MSSQL Server        
        |── 3_RunQueries.py  # Script to extract FK/TR DDL and Drop/Disable them
        └── 4_ExecuteOutputSQL.py  # Script to Create/Enable FK/TR DDL  

# Prerequisites
Fill the files with **no spaces**:
   
   *  **instance.txt:** fqdn,port,username,password for the target MSSQL server (C). 
   *  **sourceddl.txt:** fqdn,port,username,password for the target MSSQL server (A).


# Step 1
## Execution: Path\PythonDBProjects>python 1_CloneSource.py \<backup path>
1. In the source MSSQL server (A), this script will create a Clone for each Database without data
2. These Clones databases will be backup and save in the path provisioned when calling the scripts
3. All clone databases will be deleted from (A)

# Step2
## Execution: Path\PythonDBProjects>python 2_RestoreClones.py \<backup path>
1. Restores all backups in the target MSSQL Server (C), grabbing the backup files from the path provisiones when calling the python script

# Step 3
## Execution: Path\PythonDBProjects>python 3_RunQueries.py
It will:
1. Save all the commands to create FKs and enable TRs in the folder .\QueryPerDBPrInstance\output_sql_scripts 
2. Drop all FKs and Disable all TRs
3. Once it finishes, in Notepad++ look for "Error executing" for all the files in the folder \QueryPerDBPrInstance\logs
4. Run manually the commands for these databases (sql scripts in **Path\PythonDBProjects\AuxQueries**):

    a. Generate the missing create commands connecting manually to the instance.database through SSMS

    b. Save the create/enable commands in the folder .\QueryPerDBPrInstance\output_sql_scripts (name the files according to the name convention, only for clarification reasons)
    
    c. Run the Drop/ Disable commands in the target server through SSMS

# Step 4
## DMS Tool for Rollback    

# Step 5
## Execution: Path\PythonDBProjects>python 4_ExecuteOutputSQL.py
1. Compress all the log files
2. Execute the python script. It will **create the FKs and TRs** in the target server