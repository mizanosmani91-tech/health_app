-- AlterTable
ALTER TABLE "Pharmacy" ADD COLUMN     "lat" DOUBLE PRECISION,
ADD COLUMN     "lng" DOUBLE PRECISION;

-- CreateTable
CREATE TABLE "Drug" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "generic" TEXT NOT NULL DEFAULT '',
    "strength" TEXT NOT NULL DEFAULT '',
    "form" TEXT NOT NULL DEFAULT '',
    "manufacturer" TEXT NOT NULL DEFAULT '',
    "kind" TEXT NOT NULL DEFAULT 'brand',

    CONSTRAINT "Drug_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Drug_name_idx" ON "Drug"("name");

-- CreateIndex
CREATE INDEX "Drug_generic_idx" ON "Drug"("generic");

-- CreateIndex
CREATE UNIQUE INDEX "Drug_name_form_strength_manufacturer_key" ON "Drug"("name", "form", "strength", "manufacturer");
