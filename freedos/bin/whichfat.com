��!������!��� s� ��!= st�� �T32�1ɾ� �����Ĭ<	t�< t�ry<ar, <:t<?u�� ��,A<�sp�����6���!=��t7���ra�>� u^>��A���s�0 �����!r:�U"�E 	�uB=��s=�4�1ɱ��/=��u	�t�� �7�C� �>� t+��'��� ���16���32� �=�1��Z�� P�	�!X�L�!  C:\ No such local drive!
$CD-ROM or DVD drive!
$Drive is FAT12.
$Kernel limit: FAT16.
$WHICHFAT [x:]
Returns: generic:
	0=FAT32 kernel, 1=FAT16 kernel 2=/? found.
For 1 drive:
	0 not FAT, 1 no local drive, 
	12 FAT12, 16 FAT16, 32 FAT32.
$    