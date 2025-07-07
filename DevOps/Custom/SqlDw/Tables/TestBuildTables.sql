CREATE TABLE DevOpsTests.TableTests
(
	Test_ID int NOT NULL,
	Test_Name varchar(30) NOT NULL
)

WITH

(
	DISTRIBUTION = HASH (Test_id),
	CLUSTERED COLUMNSTORE INDEX
)

GO



INSERT INTO DevOpsTests.TableTests (Test_ID, Test_Name) VALUES (1,'Billy Names')

INSERT INTO DevOpsTests.TableTests (Test_ID, Test_Name) VALUES (2,'Myson Surname')

INSERT INTO DevOpsTests.TableTests (Test_ID, Test_Name) VALUES (3,'Testie Bestie')
