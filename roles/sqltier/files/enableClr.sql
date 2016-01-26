sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO
sp_configure 'clr enabled', 1;
GO
RECONFIGURE;
GO

USE [master]
GO
ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev2', FILENAME = N'D:\Temp\tempdb2.mdf' , SIZE = 8192KB , FILEGROWTH = 10%)
GO
ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev3', FILENAME = N'D:\Temp\tempdb3.mdf' , SIZE = 8192KB , FILEGROWTH = 10%)
GO
ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev4', FILENAME = N'D:\Temp\tempdb4.mdf' , SIZE = 8192KB , FILEGROWTH = 10%)
GO


USE [master]
GO
CREATE LOGIN [NT AUTHORITY\NETWORK SERVICE] FROM WINDOWS WITH DEFAULT_DATABASE=[master]
GO
EXEC master..sp_addsrvrolemember @loginame = N'NT AUTHORITY\NETWORK SERVICE', @rolename = N'sysadmin'
GO
