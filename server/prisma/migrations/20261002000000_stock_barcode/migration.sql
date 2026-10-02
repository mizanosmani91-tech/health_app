-- AlterTable
ALTER TABLE "StockItem" ADD COLUMN     "barcode" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "StockItem_pharmacyId_barcode_key" ON "StockItem"("pharmacyId", "barcode");

