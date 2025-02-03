/*
Change the value under “Maximum number of characters displayed in each column” from 256 to the max possible value, to avoid truncation on the column defenition 
Query-> Query options-> Result-> Text Maximum number of characters displayed in each column 2097152

Also Create trigger disable/enable set in line 96
*/
DROP TABLE tempdb..trgs
CREATE TABLE tempdb..trgs
(
  [databasename]          sysname,
  [schema]            sysname,
  [object]            sysname,
  name                sysname,
  is_disabled         bit,
  definition          varchar(max)
);	


INSERT tempdb..trgs
(
  [databasename],
  [schema],
  [object],
  name,
  is_disabled,
  definition
)
SELECT
  DB_NAME(), 
  s.name SchemaName, 
  o.name TableName, 
  t.name TriggerName, 
  t.is_disabled, 
  m.definition TriggerDef
FROM sys.triggers AS t
INNER JOIN sys.sql_modules AS m
  ON t.object_id = m.object_id
INNER JOIN sys.objects AS o
  ON t.parent_id = o.object_id
INNER JOIN sys.schemas AS s
  ON o.schema_id = s.schema_id
WHERE parent_class = 1; -- OBJECT_OR_COLUM

/*Enable all SQL Server Triggers*/
DECLARE @db sysname = DB_NAME();

Select 'USE ' + @db + ';'
SELECT 'ENABLE TRIGGER ' 
  + QUOTENAME([schema]) + N'.' + QUOTENAME([name]) + N' ON '  
  + QUOTENAME([schema]) + N'.' + QUOTENAME([object]) + N';'+Char(10)
FROM tempdb..trgs
WHERE is_disabled = 0
AND [databasename] = @db;


/*Disable all SQL Server Triggers*/
DECLARE @db sysname = DB_NAME();
Select 'USE ' + @db + ';'
SELECT  N'DISABLE TRIGGER ' 
  + QUOTENAME([schema]) + N'.' + QUOTENAME([name]) + N' ON '  
  + QUOTENAME([schema]) + N'.' + QUOTENAME([object]) + N';'+Char(10)+Char(13)
FROM tempdb..trgs
WHERE is_disabled = 0
AND [databasename] = @db;