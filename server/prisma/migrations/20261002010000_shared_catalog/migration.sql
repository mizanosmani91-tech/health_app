-- AlterTable
ALTER TABLE "StockItem" ADD COLUMN     "manufacturer" TEXT;

-- CreateTable
CREATE TABLE "CatalogEntry" (
    "barcode" TEXT NOT NULL,
    "pharmacyId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "genericName" TEXT,
    "form" TEXT,
    "manufacturer" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CatalogEntry_pkey" PRIMARY KEY ("barcode","pharmacyId")
);

-- CreateTable
CREATE TABLE "CatalogOverride" (
    "barcode" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "genericName" TEXT,
    "form" TEXT,
    "manufacturer" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CatalogOverride_pkey" PRIMARY KEY ("barcode")
);

-- CreateIndex
CREATE INDEX "CatalogEntry_barcode_idx" ON "CatalogEntry"("barcode");

-- AddForeignKey
ALTER TABLE "CatalogEntry" ADD CONSTRAINT "CatalogEntry_pharmacyId_fkey" FOREIGN KEY ("pharmacyId") REFERENCES "Pharmacy"("id") ON DELETE CASCADE ON UPDATE CASCADE;

